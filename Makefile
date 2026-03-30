BASE := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/../

# ─── Colors ───────────────────────────────────────────────────────────────────
RESET  := \033[0m
BOLD   := \033[1m
GREEN  := \033[32m
YELLOW := \033[33m
CYAN   := \033[36m
RED    := \033[31m

.PHONY: help install redis stop health status test-pricing test-cargo \
        start start-auth start-booking start-pricing start-payment \
        start-cargo start-admin logs git-status clean

# ─── Default ──────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "$(BOLD)BharatTruck / LogisticOS — Dev Commands$(RESET)"
	@echo "──────────────────────────────────────────────"
	@echo "$(CYAN)Setup$(RESET)"
	@echo "  make install        Install deps for all backend services"
	@echo "  make redis          Start Redis locally (brew)"
	@echo ""
	@echo "$(CYAN)Start Services$(RESET)"
	@echo "  make start          Start all 5 backend services"
	@echo "  make start-auth     Start bt-auth-service     :3001"
	@echo "  make start-booking  Start bt-booking-service  :3002"
	@echo "  make start-pricing  Start bt-pricing-service  :3003"
	@echo "  make start-payment  Start bt-payment-service  :3004"
	@echo "  make start-cargo    Start bt-cargo-ledger     :3005"
	@echo "  make start-admin    Start bt-admin-web        :3000"
	@echo ""
	@echo "$(CYAN)Check$(RESET)"
	@echo "  make health         Hit /health on all services"
	@echo "  make test-pricing   Quick pricing quote test"
	@echo "  make test-auth      Quick auth OTP test"
	@echo "  make test-cargo     Quick cargo checkpoint test"
	@echo "  make status         Git status across all repos"
	@echo "  make git-log        Recent commits across all repos"
	@echo ""
	@echo "$(CYAN)Cleanup$(RESET)"
	@echo "  make stop           Kill all running services"
	@echo "  make clean          Remove all node_modules"
	@echo ""

# ─── Setup ────────────────────────────────────────────────────────────────────
install:
	@echo "$(CYAN)Installing dependencies...$(RESET)"
	@for svc in bt-auth-service bt-booking-service bt-pricing-service bt-payment-service bt-cargo-ledger; do \
		echo "  → $$svc"; \
		cd $(BASE)$$svc && npm install --silent; \
	done
	@echo "$(GREEN)✓ All dependencies installed$(RESET)"

redis:
	@echo "$(CYAN)Starting Redis...$(RESET)"
	@redis-cli ping > /dev/null 2>&1 && echo "$(GREEN)✓ Redis already running$(RESET)" || \
		(redis-server --daemonize yes --logfile /tmp/redis-bt.log && sleep 1 && echo "$(GREEN)✓ Redis started$(RESET)")

# ─── Individual Services ──────────────────────────────────────────────────────
start-auth:
	@echo "$(CYAN)Starting bt-auth-service on :3001...$(RESET)"
	@cd $(BASE)bt-auth-service && \
		[ -f .env ] && export $$(cat .env | grep -v '^#' | xargs) || true; \
		PORT=3001 NODE_ENV=development OTP_DEV_MODE=true \
		SUPABASE_URL=$${SUPABASE_URL:-http://localhost:54321} \
		SUPABASE_SERVICE_ROLE_KEY=$${SUPABASE_SERVICE_ROLE_KEY:-dev-stub-key} \
		REDIS_URL=$${REDIS_URL:-redis://localhost:6379} \
		JWT_SECRET=$${JWT_SECRET:-dev-jwt-secret-long-enough-for-local} \
		JWT_REFRESH_SECRET=$${JWT_REFRESH_SECRET:-dev-refresh-secret-long-enough} \
		node_modules/.bin/tsx watch src/index.ts

start-booking:
	@echo "$(CYAN)Starting bt-booking-service on :3002...$(RESET)"
	@cd $(BASE)bt-booking-service && \
		[ -f .env ] && export $$(cat .env | grep -v '^#' | xargs) || true; \
		PORT=3002 NODE_ENV=development \
		node_modules/.bin/tsx watch src/index.ts

start-pricing:
	@echo "$(CYAN)Starting bt-pricing-service on :3003...$(RESET)"
	@cd $(BASE)bt-pricing-service && \
		PORT=3003 NODE_ENV=development \
		node_modules/.bin/tsx watch src/index.ts

start-payment:
	@echo "$(CYAN)Starting bt-payment-service on :3004...$(RESET)"
	@cd $(BASE)bt-payment-service && \
		[ -f .env ] && export $$(cat .env | grep -v '^#' | xargs) || true; \
		PORT=3004 NODE_ENV=development \
		node_modules/.bin/tsx watch src/index.ts

start-cargo:
	@echo "$(CYAN)Starting bt-cargo-ledger on :3005...$(RESET)"
	@cd $(BASE)bt-cargo-ledger && \
		PORT=3005 NODE_ENV=development BLOCKCHAIN_ENABLED=false \
		node_modules/.bin/tsx watch src/index.ts

start-admin:
	@echo "$(CYAN)Starting bt-admin-web on :3000...$(RESET)"
	@cd $(BASE)bt-admin-web && npm run dev

# ─── Start All (background) ───────────────────────────────────────────────────
start: redis
	@echo "$(CYAN)Starting all backend services...$(RESET)"
	@mkdir -p /tmp/bt-logs
	@cd $(BASE)bt-auth-service && \
		( [ -f .env ] && export $$(cat .env | grep -v '^#' | xargs) || true; \
		PORT=3001 NODE_ENV=development OTP_DEV_MODE=true \
		SUPABASE_URL=$${SUPABASE_URL:-http://localhost:54321} \
		SUPABASE_SERVICE_ROLE_KEY=$${SUPABASE_SERVICE_ROLE_KEY:-dev-stub-key} \
		REDIS_URL=$${REDIS_URL:-redis://localhost:6379} \
		JWT_SECRET=$${JWT_SECRET:-dev-jwt-secret-long-enough-for-local} \
		JWT_REFRESH_SECRET=$${JWT_REFRESH_SECRET:-dev-refresh-secret-long-enough} \
		node_modules/.bin/tsx watch src/index.ts > /tmp/bt-logs/auth.log 2>&1 ) & \
		echo $$! > /tmp/bt-auth.pid
	@cd $(BASE)bt-booking-service && \
		( [ -f .env ] && export $$(cat .env | grep -v '^#' | xargs) || true; \
		PORT=3002 NODE_ENV=development \
		node_modules/.bin/tsx watch src/index.ts > /tmp/bt-logs/booking.log 2>&1 ) & \
		echo $$! > /tmp/bt-booking.pid
	@cd $(BASE)bt-pricing-service && \
		( PORT=3003 NODE_ENV=development \
		node_modules/.bin/tsx watch src/index.ts > /tmp/bt-logs/pricing.log 2>&1 ) & \
		echo $$! > /tmp/bt-pricing.pid
	@cd $(BASE)bt-payment-service && \
		( [ -f .env ] && export $$(cat .env | grep -v '^#' | xargs) || true; \
		PORT=3004 NODE_ENV=development \
		node_modules/.bin/tsx watch src/index.ts > /tmp/bt-logs/payment.log 2>&1 ) & \
		echo $$! > /tmp/bt-payment.pid
	@cd $(BASE)bt-cargo-ledger && \
		( PORT=3005 NODE_ENV=development BLOCKCHAIN_ENABLED=false \
		node_modules/.bin/tsx watch src/index.ts > /tmp/bt-logs/cargo.log 2>&1 ) & \
		echo $$! > /tmp/bt-cargo.pid
	@sleep 4
	@$(MAKE) health

# ─── Stop ─────────────────────────────────────────────────────────────────────
stop:
	@echo "$(YELLOW)Stopping all services...$(RESET)"
	@for f in /tmp/bt-auth.pid /tmp/bt-booking.pid /tmp/bt-pricing.pid /tmp/bt-payment.pid /tmp/bt-cargo.pid; do \
		[ -f $$f ] && kill $$(cat $$f) 2>/dev/null && rm $$f || true; \
	done
	@pkill -f "tsx watch src/index.ts" 2>/dev/null || true
	@echo "$(GREEN)✓ All services stopped$(RESET)"

# ─── Health Checks ────────────────────────────────────────────────────────────
health:
	@echo ""
	@echo "$(BOLD)Service Health$(RESET)"
	@echo "──────────────────────────────────────────────"
	@for port_svc in "3001:auth-service" "3002:booking-service" "3003:pricing-service" "3004:payment-service" "3005:cargo-ledger"; do \
		port=$${port_svc%%:*}; svc=$${port_svc##*:}; \
		result=$$(curl -sf http://localhost:$$port/health 2>/dev/null); \
		if [ $$? -eq 0 ]; then \
			echo "  $(GREEN)✓$(RESET) bt-$$svc    :$$port  UP"; \
		else \
			echo "  $(RED)✗$(RESET) bt-$$svc    :$$port  DOWN (run: make start-$$svc)"; \
		fi; \
	done
	@echo ""

# ─── Quick Tests ──────────────────────────────────────────────────────────────
test-auth:
	@echo "$(CYAN)Testing bt-auth-service OTP flow...$(RESET)"
	@echo "\n→ send-otp (invalid phone):"
	@curl -s -X POST http://localhost:3001/auth/send-otp \
		-H 'Content-Type: application/json' \
		-d '{"phone":"123"}' | python3 -m json.tool
	@echo "\n→ send-otp (valid phone, dev mode):"
	@curl -s -X POST http://localhost:3001/auth/send-otp \
		-H 'Content-Type: application/json' \
		-d '{"phone":"9876543210"}' | python3 -m json.tool

test-pricing:
	@echo "$(CYAN)Testing bt-pricing-service...$(RESET)"
	@echo "\n→ Quote: HCV, 150km, heavy machinery, 8000kg:"
	@curl -s -X POST http://localhost:3003/quote \
		-H 'Content-Type: application/json' \
		-d '{"distance_km":150,"vehicle_type":"hcv","load_type":"heavy_machinery","weight_kg":8000}' \
		| python3 -m json.tool
	@echo "\n→ Quote: Mini truck, 30km, general, 500kg:"
	@curl -s -X POST http://localhost:3003/quote \
		-H 'Content-Type: application/json' \
		-d '{"distance_km":30,"vehicle_type":"mini_truck","load_type":"general","weight_kg":500}' \
		| python3 -m json.tool

test-cargo:
	@echo "$(CYAN)Testing bt-cargo-ledger checkpoint + Merkle hash...$(RESET)"
	@echo "\n→ Record a pickup checkpoint:"
	@curl -s -X POST http://localhost:3005/shipments/checkpoint \
		-H 'Content-Type: application/json' \
		-d '{ \
			"shipment_id":"00000000-0000-0000-0000-000000000001", \
			"leg_id":"00000000-0000-0000-0000-000000000002", \
			"checkpoint_type":"pickup", \
			"lat":19.0760, "lng":72.8777, \
			"address":"Dharavi, Mumbai", \
			"pieces_count":10, "weight_kg":500 \
		}' | python3 -m json.tool

# ─── Git ──────────────────────────────────────────────────────────────────────
status:
	@echo "$(BOLD)Git Status — All Repos$(RESET)"
	@echo "──────────────────────────────────────────────"
	@for repo in LogisticOS bt-auth-service bt-booking-service bt-pricing-service bt-payment-service bt-cargo-ledger bt-driver-app bt-shipper-app bt-admin-web; do \
		echo "$(CYAN)$$repo$(RESET):"; \
		cd $(BASE)$$repo && git status --short 2>/dev/null || echo "  (no git)"; \
		echo ""; \
	done

git-log:
	@echo "$(BOLD)Recent Commits — All Repos$(RESET)"
	@echo "──────────────────────────────────────────────"
	@for repo in LogisticOS bt-auth-service bt-booking-service bt-pricing-service bt-payment-service bt-cargo-ledger bt-driver-app bt-shipper-app bt-admin-web; do \
		echo "$(CYAN)$$repo$(RESET):"; \
		cd $(BASE)$$repo && git log --oneline -3 2>/dev/null || echo "  (no commits)"; \
		echo ""; \
	done

# ─── Logs ─────────────────────────────────────────────────────────────────────
logs:
	@echo "$(BOLD)Live logs — all services$(RESET)  (Ctrl+C to stop)"
	@tail -f /tmp/bt-logs/*.log 2>/dev/null || echo "$(RED)No services running. Run: make start$(RESET)"

logs-auth:
	@tail -f /tmp/bt-logs/auth.log 2>/dev/null || echo "$(RED)auth-service not running$(RESET)"

logs-booking:
	@tail -f /tmp/bt-logs/booking.log 2>/dev/null || echo "$(RED)booking-service not running$(RESET)"

logs-cargo:
	@tail -f /tmp/bt-logs/cargo.log 2>/dev/null || echo "$(RED)cargo-ledger not running$(RESET)"

# ─── Clean ────────────────────────────────────────────────────────────────────
clean:
	@echo "$(YELLOW)Removing node_modules from all services...$(RESET)"
	@for svc in bt-auth-service bt-booking-service bt-pricing-service bt-payment-service bt-cargo-ledger; do \
		rm -rf $(BASE)$$svc/node_modules && echo "  ✓ $$svc"; \
	done
	@echo "$(GREEN)Done. Run 'make install' to reinstall.$(RESET)"
