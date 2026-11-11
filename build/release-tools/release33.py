"""Pythilo 1.0 (33): withdraw the waiting submission, update metadata and screenshots,
select build 33 and submit again. Every step prints what it read back."""
import hashlib, json, os, sys, time, urllib.request
import asc

APP = asc.APP
VERSION_ID = "82001a0a-ab72-4c32-b715-52b1338d5866"
REPO = os.path.expanduser("~/dev/pythilo")
META = json.load(open(f"{REPO}/docs/app-store/en-US.json"))
SHOTS = f"{REPO}/docs/app-store/screenshots/en-US"

def version_state():
    return asc.call("GET", f"/appStoreVersions/{VERSION_ID}")["data"]["attributes"]["appStoreState"]

def withdraw():
    for sub in asc.call("GET", f"/reviewSubmissions?filter[app]={APP}&limit=10")["data"]:
        state = sub["attributes"].get("state")
        if state == "IN_REVIEW":
            raise SystemExit("already in review; not withdrawing")
        if state in ("WAITING_FOR_REVIEW", "READY_FOR_REVIEW", "UNRESOLVED_ISSUES"):
            asc.call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"canceled": True}}})
            print("canceling", sub["id"], state)
    for _ in range(60):
        state = version_state()
        busy = [s for s in asc.call("GET", f"/reviewSubmissions?filter[app]={APP}&limit=10")["data"] if s["attributes"].get("state") in ("CANCELING", "WAITING_FOR_REVIEW", "READY_FOR_REVIEW")]
        print("version", state, "open", len(busy))
        if state in ("DEVELOPER_REJECTED", "PREPARE_FOR_SUBMISSION", "REJECTED") and not busy:
            return
        time.sleep(10)
    raise SystemExit("withdrawal did not settle")

def localization():
    return next(x for x in asc.call("GET", f"/appStoreVersions/{VERSION_ID}/appStoreVersionLocalizations")["data"] if x["attributes"]["locale"] == "en-US")

def metadata():
    loc = localization()
    attrs = {k: META[k] for k in ("description", "keywords", "promotionalText", "marketingUrl", "supportUrl")}
    asc.call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
    review = asc.call("GET", f"/appStoreVersions/{VERSION_ID}/appStoreReviewDetail")["data"]
    asc.call("PATCH", f"/appStoreReviewDetails/{review['id']}", {"data": {"type": "appStoreReviewDetails", "id": review["id"], "attributes": {"notes": META["reviewNotes"]}}})
    back = localization()["attributes"]
    print("metadata matches", all(back[k] == attrs[k] for k in attrs))

def upload(set_id, path):
    data = open(path, "rb").read()
    shot = asc.call("POST", "/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        request = urllib.request.Request(op["url"], data=part, method=op["method"])
        for header in op.get("requestHeaders", []):
            request.add_header(header["name"], header["value"])
        urllib.request.urlopen(request, timeout=120, context=asc._SSL).read()
    asc.call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return shot["id"]

def screenshots():
    loc = localization()
    sets = asc.call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    files = sorted(f for f in os.listdir(SHOTS) if f.endswith(".jpg"))
    for s in sets:
        kind = s["attributes"]["screenshotDisplayType"]
        wanted = [f for f in files if ("ipad" in f) == ("IPAD" in kind)]
        for old in asc.call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
            asc.call("DELETE", f"/appScreenshots/{old['id']}")
        ids = [upload(s["id"], os.path.join(SHOTS, f)) for f in wanted]
        asc.call("PATCH", f"/appScreenshotSets/{s['id']}/relationships/appScreenshots", {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
        print(kind, wanted)

def attach(build_number):
    build = asc.call("GET", f"/builds?filter[app]={APP}&filter[version]={build_number}&filter[preReleaseVersion.version]=1.0&limit=5")["data"][0]
    print("build", build_number, build["attributes"]["processingState"])
    asc.call("PATCH", f"/appStoreVersions/{VERSION_ID}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    print("selected", asc.call("GET", f"/appStoreVersions/{VERSION_ID}/build")["data"]["attributes"]["version"])

def wait_screenshots():
    loc = localization()
    for _ in range(60):
        states = []
        for s in asc.call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
            states += [x["attributes"]["assetDeliveryState"]["state"] for x in asc.call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]]
        print("screenshots", states)
        if states and all(x == "COMPLETE" for x in states): return
        if any(x == "FAILED" for x in states): raise SystemExit("a screenshot failed processing")
        time.sleep(10)

def submit():
    sub = asc.call("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
    asc.call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}})
    asc.call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print("submitted", sub["id"])
    for s in asc.call("GET", f"/reviewSubmissions?filter[app]={APP}&limit=3")["data"]:
        print("submission", s["id"], s["attributes"].get("state"), s["attributes"].get("submittedDate"))
    print("version", version_state())

if __name__ == "__main__":
    step = sys.argv[1]
    if step == "all":
        withdraw(); metadata(); screenshots(); wait_screenshots(); attach(sys.argv[2]); submit()
    else:
        globals()[step](*sys.argv[2:])
