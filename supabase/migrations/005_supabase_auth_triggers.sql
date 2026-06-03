-- Migration 005: Supabase Auth integration triggers
--
-- These triggers wire auth.users ↔ public.users so that Supabase Auth
-- is the single source of truth for authentication.

-- ── 1. On new auth.users row → insert into public.users ─────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.users (auth_id, phone_number, email, role, full_name)
  VALUES (
    NEW.id,
    NEW.phone,
    NEW.email,
    COALESCE((NEW.raw_user_meta_data->>'role')::public.user_role, 'shipper'),
    NEW.raw_user_meta_data->>'full_name'
  )
  ON CONFLICT (auth_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ── 2. On new public.users row with role='driver' → create drivers row ───────

CREATE OR REPLACE FUNCTION public.handle_new_driver()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NEW.role = 'driver' THEN
    INSERT INTO public.drivers (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_user_created_ensure_driver ON public.users;
CREATE TRIGGER on_user_created_ensure_driver
  AFTER INSERT ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_driver();

-- ── 3. On auth.users metadata update → sync to public.users ─────────────────

CREATE OR REPLACE FUNCTION public.handle_user_metadata_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF OLD.raw_user_meta_data IS DISTINCT FROM NEW.raw_user_meta_data THEN
    UPDATE public.users
    SET
      full_name = COALESCE(
        NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
        full_name
      ),
      role = COALESCE(
        NULLIF(NEW.raw_user_meta_data->>'role', '')::public.user_role,
        role
      )
    WHERE auth_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_metadata_update();

-- ── 4. On public.users role updated to 'driver' → ensure drivers row ─────────

CREATE OR REPLACE FUNCTION public.handle_user_role_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NEW.role = 'driver' AND (OLD.role IS NULL OR OLD.role != 'driver') THEN
    INSERT INTO public.drivers (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_user_role_updated ON public.users;
CREATE TRIGGER on_user_role_updated
  AFTER UPDATE OF role ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_role_update();
