#!/usr/bin/env python3
"""Generate the BharatTruck MVP Pilot quick-read report PDF."""

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable, KeepTogether
)

# ---- Brand palette ----
NAVY = colors.HexColor("#0F2A43")
BLUE = colors.HexColor("#1763B6")
AMBER = colors.HexColor("#C8761B")
RED = colors.HexColor("#B23A2E")
GREEN = colors.HexColor("#2E7D4F")
LIGHT = colors.HexColor("#EEF3F8")
LIGHTAMBER = colors.HexColor("#FBF3E8")
GREY = colors.HexColor("#5B6770")
LINE = colors.HexColor("#D4DCE4")

styles = getSampleStyleSheet()

def S(name, **kw):
    base = kw.pop("parent", styles["Normal"])
    return ParagraphStyle(name, parent=base, **kw)

title_s   = S("title", fontName="Helvetica-Bold", fontSize=18, textColor=NAVY, leading=21, spaceAfter=2)
sub_s     = S("sub", fontName="Helvetica", fontSize=9.5, textColor=GREY, leading=13, spaceAfter=2)
h2_s      = S("h2", fontName="Helvetica-Bold", fontSize=11.5, textColor=BLUE, leading=14, spaceBefore=10, spaceAfter=4)
body_s    = S("body", fontName="Helvetica", fontSize=9.2, textColor=colors.HexColor("#1C2733"), leading=12.6, spaceAfter=4)
bullet_s  = S("bullet", parent=body_s, leftIndent=10, bulletIndent=0, spaceAfter=2.5)
cell_s    = S("cell", fontName="Helvetica", fontSize=8.4, textColor=colors.HexColor("#1C2733"), leading=10.8)
cellb_s   = S("cellb", parent=cell_s, fontName="Helvetica-Bold")
cellw_s   = S("cellw", parent=cell_s, textColor=colors.white)
cellwb_s  = S("cellwb", parent=cellw_s, fontName="Helvetica-Bold")
callout_s = S("callout", fontName="Helvetica", fontSize=9, textColor=colors.HexColor("#1C2733"), leading=12.5)
calloutb_s= S("calloutb", parent=callout_s, fontName="Helvetica-Bold", textColor=RED)

def bullet(txt, color=BLUE):
    hexc = "#" + color.hexval()[2:]
    return Paragraph(f'<font color="{hexc}">&#9642;</font>&nbsp;&nbsp;{txt}', bullet_s)

def callout(title, body, accent=RED, bg=LIGHTAMBER):
    inner = [Paragraph(title, calloutb_s), Spacer(1, 2), Paragraph(body, callout_s)]
    t = Table([[inner]], colWidths=[170*mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), bg),
        ("LEFTPADDING", (0,0), (-1,-1), 9),
        ("RIGHTPADDING", (0,0), (-1,-1), 9),
        ("TOPPADDING", (0,0), (-1,-1), 7),
        ("BOTTOMPADDING", (0,0), (-1,-1), 7),
        ("LINEBEFORE", (0,0), (0,-1), 3, accent),
    ]))
    return t

def status_table(rows):
    data = [[Paragraph("Component", cellwb_s), Paragraph("Status", cellwb_s), Paragraph("Detail", cellwb_s)]]
    for c, s, d in rows:
        data.append([Paragraph(c, cellb_s), Paragraph(s, cell_s), Paragraph(d, cell_s)])
    t = Table(data, colWidths=[38*mm, 26*mm, 106*mm], repeatRows=1)
    style = [
        ("BACKGROUND", (0,0), (-1,0), NAVY),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
        ("GRID", (0,0), (-1,-1), 0.4, LINE),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING", (0,0), (-1,-1), 6),
        ("TOPPADDING", (0,0), (-1,-1), 4),
        ("BOTTOMPADDING", (0,0), (-1,-1), 4),
    ]
    t.setStyle(TableStyle(style))
    return t

def timeline_table(rows):
    data = [[Paragraph("Wk", cellwb_s), Paragraph("Focus", cellwb_s), Paragraph("Done when…", cellwb_s)]]
    for w, f, e in rows:
        data.append([Paragraph(w, cellb_s), Paragraph(f, cell_s), Paragraph(e, cell_s)])
    t = Table(data, colWidths=[12*mm, 92*mm, 66*mm], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), BLUE),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
        ("GRID", (0,0), (-1,-1), 0.4, LINE),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING", (0,0), (-1,-1), 6),
        ("TOPPADDING", (0,0), (-1,-1), 3.5),
        ("BOTTOMPADDING", (0,0), (-1,-1), 3.5),
    ]))
    return t

def inputs_table(rows):
    data = [[Paragraph("Input needed", cellwb_s), Paragraph("From", cellwb_s), Paragraph("Why it blocks testing", cellwb_s)]]
    for i, fr, w in rows:
        data.append([Paragraph(i, cellb_s), Paragraph(fr, cell_s), Paragraph(w, cell_s)])
    t = Table(data, colWidths=[44*mm, 28*mm, 98*mm], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), AMBER),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHTAMBER]),
        ("GRID", (0,0), (-1,-1), 0.4, LINE),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING", (0,0), (-1,-1), 6),
        ("TOPPADDING", (0,0), (-1,-1), 4),
        ("BOTTOMPADDING", (0,0), (-1,-1), 4),
    ]))
    return t

story = []

# ---- Header ----
story.append(Paragraph("BharatTruck — MVP Pilot Plan &amp; Claude Max Upgrade", title_s))
story.append(Paragraph("To: Shambhu Sir &nbsp;·&nbsp; From: Aditya (DeltaOS) &nbsp;·&nbsp; 8 June 2026 &nbsp;·&nbsp; Quick read", sub_s))
story.append(HRFlowable(width="100%", thickness=1.2, color=BLUE, spaceBefore=4, spaceAfter=2))

# ---- Summary ----
story.append(Paragraph("Where we stand", h2_s))
story.append(Paragraph(
    "The backend spine and both web apps (driver + shipper) are built and live on GCP Cloud Run. We are in "
    "<b>hardening-and-wiring mode, not greenfield</b>. To run a real pilot we don't need the entire feature catalogue — "
    "we need one end-to-end loop (post load &#8594; match &#8594; track &#8594; deliver &#8594; pay) made solid and put in "
    "front of fleet owners on a single corridor.", body_s))

story.append(status_table([
    ("Auth + KYC", "Mature", "Full Indian KYC live via Surepass (PAN, GST, Aadhaar, DL, RC, bank, face-match). Mid-migration to Supabase Auth."),
    ("Booking", "Core working", "Quote/negotiation auction + booking state machine, GPS location ingestion."),
    ("Pricing", "Static v1", "Rules engine placeholder — awaiting Sir's rate data to become real (see below)."),
    ("Payment", "Built, NOT wired", "Razorpay routes exist but not connected into the booking/delivery flow."),
    ("Cargo Ledger", "Built, NOT wired", "Multi-leg tracking + proof built, but not connected end-to-end."),
    ("Driver / Shipper apps", "Usable (web)", "Onboarding, load discovery, booking, negotiation, profiles all working."),
]))

# ---- Critical caveat ----
story.append(Spacer(1, 6))
story.append(callout(
    "Important — this cannot be called &ldquo;complete&rdquo; before testing",
    "<b>Cargo Ledger</b> and <b>Payment</b> services are prepared but <b>not yet wired into the live flow</b>. "
    "Until they are connected (delivery proof &#8594; payment release &#8594; ledger record), the MVP is functional for "
    "demos but not a finished end-to-end product. Wiring these is on the critical path below.",
    accent=RED, bg=LIGHTAMBER))

# ---- Why the $100 plan ----
story.append(Paragraph("Why the $100/mo Claude Max plan", h2_s))
story.append(Paragraph(
    "I'm a solo developer running <b>8 separate repos</b> (6 backend services + 2 apps + admin). Max's higher usage "
    "limits let me run long, uninterrupted coding sessions across all of them without hitting caps mid-task — today the "
    "single biggest drag on velocity. It handles the boilerplate-heavy ~70% (migrations, route wiring, integrations, "
    "tests, admin console) so my hours go to judgment and field work. At ~1&#8211;2% of a second developer's cost, "
    "it is a force-multiplier on the one developer we have.", body_s))

# ---- Pricing engine ----
story.append(Paragraph("Pricing engine — turning Sir's data into live quotes", h2_s))
story.append(Paragraph(
    "Sir has rate data to share (Siddharth was to handle this) that maps <b>vehicle &times; tonnage of material &times; "
    "volume occupied &#8594; the rate we earn</b>. That data is the missing core of the pricing service. The engine will:", body_s))
story.append(bullet("Take the load (material, tonnage, volume) and pick the right vehicle class from Sir's rate tables."))
story.append(bullet("Layer live <b>fuel (petrol/diesel) prices</b> and <b>toll costs</b> on the route on top of the base rate."))
story.append(bullet("Output a transparent, demand-aware quote to the shipper — replacing the current static v1 placeholder."))

# ---- Tracking + fuel analytics ----
story.append(Paragraph("Live tracking + a fuel-analytics service (Google Maps Platform)", h2_s))
story.append(Paragraph(
    "I plan to use <b>Google Maps Platform</b> for live vehicle tracking on the shipper's map, and to build a service in "
    "the same direction that estimates <b>fuel usage from vehicle speed and mileage</b>. This gives us trip-level cost "
    "analytics (fuel burn per trip/lane) that feed back into pricing accuracy and, later, fleet-owner insights.", body_s))

# ---- Inputs needed ----
story.append(Paragraph("What I need from Sir / Siddharth to test", h2_s))
story.append(inputs_table([
    ("Surepass production access", "Sir", "KYC verifications (PAN, GST, Aadhaar, DL, RC, bank) need live credentials/quota to onboard real users."),
    ("Test vehicle data (chassis no. + RC creds)", "Sir / Siddharth", "Needed to validate RC / vehicle KYC against real records before real drivers onboard."),
    ("Pricing rate data (vehicle &times; tonnage &times; volume &#8594; rate)", "Sir / Siddharth", "The core input that turns the pricing service from placeholder into real quotes."),
    ("E-way bill access / test data", "Sir", "To validate e-way bill linkage on bookings during the pilot."),
]))

# ---- Timeline ----
story.append(Paragraph("Rough timeline to pilot (~6&#8211;8 weeks, web/PWA, one corridor)", h2_s))
story.append(timeline_table([
    ("1", "Finish Supabase Auth migration; stabilise signup/login on both apps.", "Any driver/shipper reliably signs up &amp; logs in."),
    ("2", "Harden booking happy path end-to-end; add status push/SMS notifications.", "A full booking flows start&#8594;finish, no manual steps."),
    ("3", "<b>Wire Payment + Cargo Ledger</b> into the flow (delivery proof &#8594; payout &#8594; ledger).", "Money + proof move end-to-end automatically."),
    ("4", "Pricing engine on Sir's data + fuel/toll layer; Google Maps live tracking.", "Shipper sees a real quote and a live map."),
    ("5", "Fuel-analytics service v1; admin ops console for monitoring/intervention.", "I can run ops for 20 users from one screen."),
    ("6", "QA on real Android devices; onboard 3&#8211;5 friendly fleet owners (alpha).", "5 real trips completed by real users."),
    ("7&#8211;8", "Fix what alpha breaks; expand to 10&#8211;20 fleet owners on the corridor.", "Closed pilot live."),
]))

# ---- The ask ----
story.append(Paragraph("The ask", h2_s))
story.append(bullet("Approve the <b>$100/mo Claude Max plan</b> — a force-multiplier on our one developer at ~1&#8211;2% of a hire's cost.", GREEN))
story.append(bullet("Endorse the <b>web/PWA pilot</b> approach to hit the 6&#8211;8 week window (go native after the loop is validated).", GREEN))
story.append(Spacer(1, 4))
story.append(Paragraph(
    "<i>Planning docs treated as reference, not bible: they assume Expo mobile apps (we're actually on Next.js web — faster "
    "to pilot) and frame the Fleet Operator app as core (it is genuinely post-pilot; a small-truck owner uses the Driver app).</i>",
    S("foot", parent=body_s, fontSize=8, textColor=GREY, leading=11)))

doc = SimpleDocTemplate(
    "/Users/adityaroshanjoshi/Desktop/VS_Code/StartUps/LogisticOS/docs/BharatTruck_MVP_Pilot_Plan.pdf",
    pagesize=A4, leftMargin=20*mm, rightMargin=20*mm, topMargin=15*mm, bottomMargin=14*mm,
    title="BharatTruck — MVP Pilot Plan", author="Aditya (DeltaOS)")
doc.build(story)
print("OK")
