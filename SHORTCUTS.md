# Starting the server from iOS Shortcuts

iSH doesn't add any actions to the Shortcuts app (see
[ish-app/ish#59](https://github.com/ish-app/ish/issues/59)), so a Shortcut
can't run a command in iSH directly. There are two workarounds:

| | Option A: start when iSH opens | Option B: SSH (optional) |
|---|---|---|
| How | iSH runs `serve.sh start` from `~/.profile`. The Shortcut opens iSH, then Safari. | An SSH server in iSH. Shortcuts runs commands with **Run Script Over SSH**. |
| What you can do from Shortcuts | Start | Start, stop, status |
| What it adds | One line in `~/.profile` | `openssh`, a root-login service on `127.0.0.1`, an SSH key stored in Shortcuts |
| Recommended for | Most people | When you want stop/status without opening iSH |

Do the normal setup first (`./serve.sh setup`, see [README](README.md)) and
check that `./serve.sh start` works by hand.

---

## Option A: start when iSH opens

### 1. Turn on autostart (in iSH)

```sh
cd ~/iOS-websrv
./serve.sh autostart on
```

This adds one line to the end of `~/.profile`, ending in the comment
`# ish-websrv autostart`. iSH's shell runs `~/.profile` each time a new
session starts. `./serve.sh autostart off` removes the line again, and
`./serve.sh status` shows whether it's on.

Keep **keepalive on** (the `setup` default). Without it, iOS suspends iSH as
soon as the Shortcut switches to Safari, and the page never loads.

### 2. Build the Shortcut (in the Shortcuts app)

1. Tap **+** to create a new shortcut and name it something easy to say, e.g.
   **Start Web Server**. That name is also the Siri phrase.
2. Add the action **Open App** and choose **iSH**.
3. Add **Wait** and set it to **5 seconds**. iSH is emulated, and Python takes
   a few seconds to start in it; raise this if Safari shows an error because
   it opened before the server was ready.
4. Add **Open URLs** with `http://127.0.0.1:8080/` (use your port if you
   changed it).

To use it:
- **Siri:** "Hey Siri, Start Web Server."
- **Home Screen:** in the shortcut, tap the **ⓘ** (details) button, then
  **Add to Home Screen**.

### Things to know

- **`.profile` only runs when iSH starts a new session.** If iSH is already
  open in the background, the Shortcut just brings it forward. That's fine if
  the server is still running, which keepalive makes likely. If you ran
  `./serve.sh stop`, the Shortcut won't restart it; type `./serve.sh start` in
  iSH, or close iSH from the app switcher and run the Shortcut again.
- **Folder picker after an iSH restart.** iSH forgets the iOS mount when it
  restarts, so `start` opens the folder picker. Safari may open before you've
  chosen the folder. Pick the folder, then run the Shortcut again (or switch to
  Safari and reload).
- **Each new iSH window runs `.profile`.** On iPad, opening a second iSH
  window runs `start` again; it just reports "Already running".

---

## Option B (optional): control it over SSH

This follows the iSH project's
[Shortcuts workaround](https://github.com/ish-app/ish/wiki/Shortcuts-Integration-Workaround).

> **Security trade-off:** this adds an SSH server that accepts **root** logins.
> The settings below limit it to this device (`127.0.0.1`) and key-only logins,
> but anything holding the key, and therefore anyone who can run your
> shortcuts, can run any command in iSH. Skip this section if Option A is
> enough.

### 1. Install and configure sshd (in iSH)

```sh
apk add openssh
ssh-keygen -A            # create the server's host keys

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/ish-websrv.conf <<'EOF'
Port 2222
ListenAddress 127.0.0.1
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

# Show the settings sshd will actually use:
sshd -T | grep -Ei '^(port|listenaddress|permitrootlogin|passwordauthentication) '
```

The last command should show `port 2222`, `listenaddress 127.0.0.1:2222`,
`permitrootlogin without-password` (which means the same as
`prohibit-password`) and `passwordauthentication no`. If it shows the
defaults instead, your `/etc/ssh/sshd_config` doesn't read the
`sshd_config.d` folder: add this as the **first** line of that file, because
sshd uses the first value it finds for each setting:

```
Include /etc/ssh/sshd_config.d/*.conf
```

### 2. Start sshd when iSH opens

Add this line to `~/.profile` yourself. `serve.sh` doesn't manage it, so it's
clear what's running.

```sh
pgrep -x sshd >/dev/null || /usr/sbin/sshd
```

Then close and reopen iSH, or run that line by hand now.

### 3. Let Shortcuts log in with a key

1. In Shortcuts, add a **Run Script Over SSH** action (in a new shortcut,
   step 4 below).
2. Set **Authentication** to **SSH Key**, open the key entry, and tap
   **Share Public Key** to copy it.
3. In iSH:

   ```sh
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   cat >> ~/.ssh/authorized_keys     # paste the key, press Return, then Ctrl-D
   chmod 600 ~/.ssh/authorized_keys
   ```

### 4. Build the Shortcuts

All three use the same **Run Script Over SSH** settings:

| Setting | Value |
|---|---|
| Host | `127.0.0.1` |
| Port | `2222` |
| User | `root` |
| Authentication | SSH Key (from step 3) |

| Shortcut | Actions |
|---|---|
| **Start Web Server** | Open App (iSH) → Wait (5 s) → Run Script Over SSH: `/root/iOS-websrv/serve.sh start` → Open URLs `http://127.0.0.1:8080/` |
| **Stop Web Server** | Open App (iSH) → Wait (5 s) → Run Script Over SSH: `/root/iOS-websrv/serve.sh stop` → Show Result |
| **Web Server Status** | Open App (iSH) → Wait (5 s) → Run Script Over SSH: `/root/iOS-websrv/serve.sh status` → Show Result |

**Open App** comes first because sshd only answers while iSH is running. The
iSH wiki says it stops once iSH is in the background, unless keepalive is
running.

Adjust `/root/iOS-websrv` if you cloned the repo somewhere else. If Option A's
autostart is also on, opening iSH already starts the server, so the SSH
`start` will just report "Already running". That's harmless.

### Things to know

- **Mount the folder in iSH first.** Whether the iOS folder picker can appear
  when `start` runs over SSH hasn't been tested. After an iSH restart, run
  `./serve.sh start` (or Option A) in iSH itself before using these Shortcuts.

### Removing Option B

```sh
pkill -x sshd
# delete the sshd line from ~/.profile
rm /etc/ssh/sshd_config.d/ish-websrv.conf
apk del openssh
# remove the Shortcuts key from ~/.ssh/authorized_keys
```
