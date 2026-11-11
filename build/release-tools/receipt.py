"""Reads the 1.0 (<build>) release back from App Store Connect and writes its receipt.
Usage: receipt.py <build> <archive commit> <withdrawn submission note>"""
import asc, json, hashlib, os, datetime, subprocess, sys
N, COMMIT, WITHDRAWN = sys.argv[1], sys.argv[2], sys.argv[3]
REPO=os.path.expanduser("~/dev/pythilo"); V="82001a0a-ab72-4c32-b715-52b1338d5866"
META=json.load(open(f"{REPO}/docs/app-store/en-US.json")); NOTES=json.load(open(f"{REPO}/docs/app-store/testflight-{N}.json"))
b=asc.call("GET",f"/builds?filter[app]={asc.APP}&filter[version]={N}&filter[preReleaseVersion.version]=1.0&limit=1")["data"][0]
detail=asc.call("GET",f"/builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
locs=asc.call("GET",f"/builds/{b['id']}/betaBuildLocalizations")["data"]
ver=asc.call("GET",f"/appStoreVersions/{V}")["data"]["attributes"]
sel=asc.call("GET",f"/appStoreVersions/{V}/build")["data"]["attributes"]["version"]
loc=next(x for x in asc.call("GET",f"/appStoreVersions/{V}/appStoreVersionLocalizations")["data"] if x["attributes"]["locale"]=="en-US")
rev=asc.call("GET",f"/appStoreVersions/{V}/appStoreReviewDetail")["data"]["attributes"]
shots=[]
for s in asc.call("GET",f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
    for x in asc.call("GET",f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
        a=x["attributes"]; shots.append({"set":s["attributes"]["screenshotDisplayType"],"file":a["fileName"],"md5":a["sourceFileChecksum"],"state":a["assetDeliveryState"]["state"]})
folder=f"{REPO}/docs/app-store/screenshots/en-US"; local={n:hashlib.md5(open(os.path.join(folder,n),"rb").read()).hexdigest() for n in os.listdir(folder)}
sub=next(s for s in asc.call("GET",f"/reviewSubmissions?filter[app]={asc.APP}&limit=3")["data"] if s["attributes"]["state"]=="WAITING_FOR_REVIEW")
ipa=f"{REPO}/build/testflight/Export/Pythilo.ipa"
r={"checkedAt":datetime.datetime.now(datetime.timezone.utc).isoformat(),"version":"1.0","buildNumber":N,"buildID":b["id"],
 "processingState":b["attributes"]["processingState"],"internalBuildState":detail.get("internalBuildState"),
 "testNotesReadbackMatches":all(any(l["attributes"]["locale"]==k and l["attributes"]["whatsNew"]==v for l in locs) for k,v in NOTES.items()),
 "appStoreState":ver["appStoreState"],"releaseType":ver["releaseType"],"selectedBuild":sel,"reviewSubmissionID":sub["id"],
 "reviewSubmittedDate":sub["attributes"].get("submittedDate"),"withdrawnSubmission":WITHDRAWN,
 "metadataReadbackMatches":all(loc["attributes"][k]==META[k] for k in ("description","keywords","promotionalText","marketingUrl","supportUrl")) and rev["notes"]==META["reviewNotes"],
 "screenshots":shots,"screenshotsMatchRepository":all(local.get(s["file"])==s["md5"] for s in shots) and len(shots)==len(local),
 "screenshotsComplete":all(s["state"]=="COMPLETE" for s in shots),
 "archiveSourceCommit":subprocess.check_output(["git","-C",REPO,"rev-parse",COMMIT],text=True).strip(),
 "ipa":{"bytes":os.path.getsize(ipa),"sha256":hashlib.sha256(open(ipa,"rb").read()).hexdigest(),"sdk":"iphoneos27.2"},"physicalDeviceClaim":False}
json.dump(r,open(f"{REPO}/docs/app-store/release-1.0-build{N}.json","w"),indent=1)
print(json.dumps({k:v for k,v in r.items() if k!="screenshots"},indent=1))
