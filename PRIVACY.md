# Pythilo privacy

Pythilo has no account, analytics or advertising. Projects stay on your device.

Courses, Lab topics, Python package packs and optional training data download from
pythilo.com when selected. Creating a project automatically queues its required
dependencies. Optional pretrained BERT weights come from Hugging Face and its
model-delivery CDN. Those services receive ordinary resource requests and connection
information, including your IP address; your project code, lesson drafts, progress
and training results are not uploaded. Installed content works offline.

The app also contacts services when you use `pip install`, npm, Git over HTTPS,
shared rooms, or network access in your own code.

When you share a project with an AI client, the client connects directly to this
device over your local network with a token that ends when you stop sharing. It
sees that one project, and only does what you allow on the sharing screen. What
that client then does with the project is governed by its own provider's terms.

Git tokens are kept in the Keychain, on this device only.
