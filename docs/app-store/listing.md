# App Store and TestFlight materials

The owner confirmed a one-time paid app at **US$9.99** on 5 November 2026. The beta
remains free. On 11 November 2026 the owner asked for release to the App Store, set up
as Crabrix: version 1.0 is submitted for App Review with **manual** release, available in
all 175 territories and in new ones. App Privacy is published as **Data Not Collected**
(as for Crabrix, and as the privacy policy states) and the content rights declaration is
"uses third-party content", as for Crabrix. The receipt is `release-1.0-build31.json`.

`en-US.json` is the current text for the App Store draft and TestFlight: subtitle,
promotional text, description, keywords, links, beta description, What to Test and
review notes. The editable App Store draft uses manual release. Categories are
Developer Tools and Education. Website: https://pythilo.com/; support:
https://pythilo.com/support/; privacy: https://pythilo.com/legal/privacy/.

`screenshots/en-US/` contains six 1320 × 2868 iPhone JPEGs and two 2064 × 2752 iPad
JPEGs, composed from real app captures. Apple uses the API display types
`APP_IPHONE_67` and `APP_IPAD_PRO_3GEN_129` for these sets. Asset delivery must say
`COMPLETE`; reserving or uploading alone is not completion.
All eight assets reported `COMPLETE` after upload on 5 November 2026.

The age questionnaire marks shared project files as user-generated content and the
web preview as unrestricted web access (its WKWebView can follow external links).
There is no manual age override. No advertising, gambling, health or mature content
is built into Pythilo.

The public beta has no signup link: only the internal TestFlight group is enabled.
Completed internal releases and their readback receipts are recorded in `docs/STATUS.md`.
The website uses support@pythilo.com, privacy@pythilo.com and security@pythilo.com,
forwarded to the owner via Forward Email with DNS on Vercel. TestFlight feedback and
public GitHub issues are also available. The terms follow Crabrix in not choosing a
separate legal jurisdiction. App Review and release are separate from these saved draft materials.

Before a future App Review submission, settle the existing export-compliance question
in `docs/STATUS.md` (bundled OpenSSL and libgit2 HTTPS) and complete Apple's App
Privacy questionnaire against the final binary and the published privacy policy.

The current saved draft and beta descriptions cover 430 lessons in 35 courses,
100 interview tasks and 120 Labs in 15 topics. Courses, Lab categories and the whole library have explicit Download actions.
Each selection saves every lesson or Lab with all its dependencies; project source
stays local while packages, datasets and weights download only after that action. Six complete real BERT/LoRA projects train and evaluate
on the device. Compiled backends stay signed inside the application.

Build 26 Learn and Labs artwork said 430 lessons and 120 Labs/15 topics. The
PyTorch artwork explains downloading packages before offline CPU training. Apple's
replacement filenames are `03-learn-430-100.jpg`, `04-labs-120.jpg` and
`05-pytorch-downloads.jpg`; local sources retain their original filenames.
All eight assets were read back as COMPLETE on 6 November 2026. Build 26 notes
in English and Russian are saved in `testflight-26.json`. TestFlight 0.1.0 (26)
is VALID and IN_BETA_TESTING for the existing internal group, confirmed at
22:07:20 UTC on 6 November 2026. No Beta App Review submission exists; the
App Store draft stays PREPARE_FOR_SUBMISSION with MANUAL release.

Build 27 updates the saved draft descriptions and beta instructions to explicit
whole-course, whole-category and whole-library downloads. Creating/opening a
project, Run and Keep as project never start transfers. Learn and Labs artwork
now shows the actual Download entire course and Download entire category
controls. New Apple filenames are `03-learn-explicit-offline27.jpg` and
`04-labs-explicit-offline27.jpg`; the other six assets remain. All eight assets
were read back as COMPLETE on 7 November 2026 local time. Receipt:
`build/release-receipts/manual27-screenshots.json`. English and Russian notes
are saved in `testflight-27.json`.

TestFlight 0.1.0 (27) is VALID and IN_BETA_TESTING for the existing internal group,
confirmed at 2026-11-06T23:57:45.095Z. Both note locales match `testflight-27.json`.
No Beta App Review submission exists; the App Store draft remains
PREPARE_FOR_SUBMISSION with MANUAL release. Final readback:
`build/release-receipts/testflight-27-ready.json`.

Build 31 (version 1.0) replaces the Store screenshots 02, 03 and 04 with new captures of
terminal tabs (Django tests in a second tab while the server runs), Learn and Labs, in
the same frames; the other five are unchanged. The description says 19 Lab topics and
mentions terminal tabs, lesson search and the pinned Next. The reviewer notes describe
the terminal-tab path and no longer say that no submission is requested.
