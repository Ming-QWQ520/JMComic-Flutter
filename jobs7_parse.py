import json
d = json.load(open("jobs7.json", encoding="utf-8"))
for j in d.get("jobs", []):
    print("JOB:", j["name"], "|", j["status"], "|", j["conclusion"])
    for s in j.get("steps", []):
        c = s.get("conclusion")
        if c not in ("success", "skipped", None):
            print("  FAIL-STEP:", s["name"], "|", c")

