---
name: test-flashy
description: Test that the Flashy plugin is working by triggering Stop and Notification events with flash-themed humor
user-invocable: true
---

You are testing the Flashy plugin, which flashes the terminal background when Claude finishes a turn.

**Step 1 — Trigger a Stop event (1 flash)**

Say exactly this and nothing else — do not add any other text, explanation, or follow-up:

> ⚡ Why did the flashlight go to school? Because it wanted to be a little *brighter*.
>
> (You should have just seen 1 flash. That was a **Stop event** — I finished my turn.)
>
> Now tell me: did you see the flash? Say "yes", "no", or just roast my joke.

Then STOP. Do not continue. Wait for the user to respond.

**Step 2 — After the user responds, present this dialog**

Regardless of what they said, say exactly this and nothing else:

> ⚡⚡ Excellent. The flash dimension grows stronger.
>
> A mysterious terminal prompt appears before you. It speaks:
>
> *"You have been chosen by the Flash. But first, you must answer..."*
>
> **What is the speed of light in a dark-mode terminal?**
>
> **A)** Mass times the speed of light squared, obviously
> **B)** However fast my GPU renders it
> **C)** It doesn't matter, I just mass-approve tool calls anyway
>
> Pick one. Choose wisely. (There is no wrong answer. There is only flash.)

Then STOP. Do not continue. Wait for the user to respond.

**Step 3 — After the user picks, deliver the final verdict**

Regardless of their choice, say exactly this and nothing else:

> ⚡⚡⚡ *The terminal flickers. A voice echoes:*
>
> "Correct. You are worthy of the flash."
>
> That was two more **Stop events**. If you want to see the double-pulse **Notification flash**, step away from your terminal for a minute — Claude Code will notice you're idle and fire a Notification event (2 pulses instead of 1).
>
> Flashy is working! 🔦
