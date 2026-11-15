# MiRMiR for Mac: Privacy Policy

_Last updated: 14 November 2026_

MiRMiR for Mac ("the app") runs language models on your own computer. This
policy explains what happens to your data. Short version: it stays with you.

## What we collect

Nothing. The app has no account, no analytics, no crash reporting and no
advertising, and it does not track you. We, the makers of MiRMiR, receive no
data from the app.

## What stays on your Mac

Your prompts, chats, attached images, downloaded models, settings and logs are
stored on your Mac, in the app's sandbox container. API keys for remote
servers are stored in your login Keychain. Deleting the app and its container
removes them.

## When the app connects to the internet

- **Hugging Face.** When you search for or download a model, the app contacts
  huggingface.co. Hugging Face receives the request like any other web request
  (for example your IP address and the model you asked for). Their privacy
  policy applies: https://huggingface.co/privacy
- **Servers you add.** When you add a MiRMiR server running on another
  machine, the app sends your prompts to that server, over TLS. You choose and
  control those servers.
- **Remote Access.** If you turn it on, other machines holding an API key you
  created can use this Mac's models. It is off by default.

The app makes no other network connections.

## Local API

The bundled server offers an HTTP API on 127.0.0.1 (this Mac only), so your
own tools can use the loaded model. It is not reachable from other machines
unless you turn on Remote Access.

## Children

The app is not directed at children.

## Changes

If this policy changes, the new version will be published at this address
with a new date.

## Contact

Questions: https://mirmir.tech/contact
