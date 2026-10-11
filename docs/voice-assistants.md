# Siri, Android shortcuts and Google Home

Houston has a small **automation API**. A shortcut on your phone (or Home Assistant) can ask for the Apollo's status or switch it, without opening the app:

| What | Method | URL |
|---|---|---|
| Status, as one sentence to read aloud | `GET` | `http://<apollo>:8088/api/v1/say` |
| Status, as JSON | `GET` | `http://<apollo>:8088/api/v1/status` |
| Do something | `POST` | `http://<apollo>:8088/api/v1/action/<action>` |

Actions: `start`, `stop`, `eco`, `balanced`, `turbo`, `node-start`, `node-stop`, and on an Apollo III also `super_eco` and `custom-14` (any 5–20).

Every request needs the header `Authorization: Bearer <your key>`.

## 1. Get a key

Open Houston › **Settings › Siri, Google & shortcuts › Create a key**. Copy it.

- The key can only use the endpoints above: read the status and run those actions. It can't change your schedule, settings or Apollo password.
- **New key** replaces it (old shortcuts stop working); **Turn off** disables shortcut access completely.
- Treat it like a password. Houston slows down and then blocks repeated wrong keys.

`<apollo>` is the address you open Houston at: the home address (e.g. `192.168.1.50`) works only at home. The **Tailscale** address (`100.x.y.z`, or the name `apollo`) works at home *and* away, as long as Tailscale is connected on the phone.

Actions answer right away ("Switching to Turbo.") and run in the background. Starting takes about a minute, and the result appears on Houston's **Activity** tab marked *Shortcut*.

---

## 2. iPhone and iPad: Siri

Uses the built-in **Shortcuts** app. Nothing to install.

### "Hey Siri, Apollo status"

1. Open **Shortcuts**, tap **+**.
2. Add the action **Get Contents of URL**. Enter `http://100.x.y.z:8088/api/v1/say` (your address).
3. Tap the **›** arrow on that action: *Method* **GET**. Under *Headers* add a header: key `Authorization`, value `Bearer hk_…` (your key, with the word Bearer and a space in front).
4. Add the action **Speak Text** (it uses *Contents of URL* automatically).
5. Name the shortcut **Apollo status** (tap the name at the top).

Say "Hey Siri, Apollo status". Siri answers with something like: *"Your Apollo is mining at 5.75 terahash in Eco mode. Hashboard temperature 158 degrees Fahrenheit. Using 209 watts. The Bitcoin node is running. Bitcoin is at 123,456 USD, up 2.1 percent today."*

### "Hey Siri, Apollo Turbo" (and the rest)

Same steps, with three changes: URL `…/api/v1/action/turbo`, *Method* **POST**, and name it **Apollo Turbo**. Duplicate it (long-press › Duplicate) for `eco`, `stop`, `start` and so on.

### Other ways to run them

- Add a shortcut to the **Home Screen** (share icon › Add to Home Screen), as a **widget**, to **Control Center**, to the **Action button** (iPhone 15 Pro and later), or to **Back Tap** (Settings › Accessibility › Touch › Back Tap).
- **Automations** tab: run one when you leave home or at a time of day. (The schedule in Houston is usually the better tool for fixed times.)
- Away from home, Siri can only reach the Apollo if Tailscale is connected. In the Tailscale app, turn on **VPN On Demand** so it connects by itself.

---

## 3. Android

Android has no built-in equivalent of Apple Shortcuts. The free, open-source **HTTP Shortcuts** app ([Google Play](https://play.google.com/store/apps/details?id=ch.rmy.android.http_shortcuts), [F-Droid](https://f-droid.org/packages/ch.rmy.android.http_shortcuts/)) does the same job.

1. Install HTTP Shortcuts, tap **+** › *Regular shortcut*.
2. **Basic request settings**: method `POST`, URL `http://100.x.y.z:8088/api/v1/action/turbo`.
3. **Request headers**: add `Authorization` = `Bearer hk_…`.
4. **Response handling**: show the response as a *toast* (a short pop-up message).
5. Name it **Apollo Turbo**. Repeat for the other actions, and make a `GET …/api/v1/say` one for status (show its response in a dialog).

Then put them where you want them: a **home-screen** icon or **widget** (long-press the shortcut › *Place on home screen*), or a **Quick Settings tile** (Settings › *Quick Settings tiles*), so it's one swipe down and one tap.

**Voice on Android, honestly:** Google's assistant (now Gemini on most phones) can open apps, but it has no dependable way to run another app's shortcut by name. A home-screen button or Quick Settings tile is the reliable option. For true voice control, use Google Home through Home Assistant (next section), or an automation app like Tasker if you already use one.

---

## 4. Google Home and Nest speakers

**No direct, simple route exists.** For "Hey Google, turn on the Apollo" to work, a device has to be added to Google Home through a *cloud integration*. That means a service on the internet that Google calls, an account-linking setup, and Google's review process. That's far too heavy (and too exposed) for a home miner, so Houston doesn't do it on its own.

**The practical route is [Home Assistant](https://www.home-assistant.io/)**, if you run it or are happy to: Houston becomes a switch and a mode selector inside Home Assistant, and Home Assistant shares them with Google Home. [Home Assistant Cloud (Nabu Casa)](https://support.nabucasa.com/hc/en-us/articles/25619376817053) makes that a few clicks; it's a paid subscription that also supports the Home Assistant project. Free manual setup is possible but involved.

Once set up you can say:
- "Hey Google, turn on the Apollo" / "turn off the Apollo"
- "Hey Google, set Apollo mode to Turbo"
- and use them in Google Home routines (e.g. Eco when you get home).

### Home Assistant configuration

Add to `configuration.yaml`, then put your address and key in `secrets.yaml`:

```yaml
# secrets.yaml  (your Apollo's address and your key)
houston_action_url: "http://192.168.1.50:8088/api/v1/action/{{ action }}"
houston_status_url: "http://192.168.1.50:8088/api/v1/status"
houston_auth: "Bearer hk_your_key_here"
```

```yaml
# configuration.yaml
rest_command:
  houston:
    url: !secret houston_action_url   # {{ action }} is filled in by each call below
    method: post
    headers:
      Authorization: !secret houston_auth
    timeout: 20

rest:
  - resource: !secret houston_status_url
    headers:
      Authorization: !secret houston_auth
    scan_interval: 60
    sensor:
      - name: "Apollo status"
        value_template: "{{ value_json.status }}"
        json_attributes: [ghs, watts, tempC, node, mode, text]
      - name: "Apollo hashrate"
        value_template: "{{ ((value_json.ghs or 0) / 1000) | round(2) }}"
        unit_of_measurement: "TH/s"
      - name: "Apollo power"
        value_template: "{{ value_json.watts or 0 }}"
        unit_of_measurement: "W"
        device_class: power

template:
  - switch:
      - name: "Apollo"
        state: "{{ is_state('sensor.apollo_status', 'online') }}"
        turn_on:
          action: rest_command.houston
          data: { action: start }
        turn_off:
          action: rest_command.houston
          data: { action: stop }
    select:
      - name: "Apollo mode"
        state: "{{ (state_attr('sensor.apollo_status', 'mode') or 'eco') | replace('_', ' ') | title }}"
        options: "{{ ['Eco', 'Balanced', 'Turbo'] }}"   # Apollo III: add 'Super Eco'
        select_option:
          action: rest_command.houston
          data:
            action: "{{ option | lower | replace(' ', '_') }}"
```

Restart Home Assistant, check that **Apollo** (switch) and **Apollo mode** (select) work on a dashboard, then expose both to Google Assistant (Settings › Voice assistants › Expose) and ask Google to "sync my devices".

> Tested against Houston with a stand-in Apollo, not yet with a live Home Assistant + Google Home setup. Please report back if anything needs adjusting.

### What about Matter?

Google Home, Apple Home and Alexa all support **Matter**, the newer local smart-home standard. Houston could in principle appear as a Matter device (a plug for on/off, a mode selector). That needs a Matter stack running on the Apollo and a pairing flow. It's possible future work, not something that's ready today.

---

## Security notes

- The key lives on the Apollo in Houston's private state folder (readable only by Houston), and in your shortcuts.
- Actions run with the Apollo sign-in Houston already keeps for the schedule. The key never reveals that sign-in or your password.
- Shortcuts reach the Apollo only on your home network or through your private Tailscale network. Nothing is opened to the internet.
