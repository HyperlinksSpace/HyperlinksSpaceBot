# Investigation: User's message disappears when sending (streaming / drafts)

## What we observe

When the user sends a message (especially in a thread), their own message bubble **disappears** for a moment and then **reappears**. The bot's response is not the one disappearing — the **user's** message is.

## Exact cause (root cause)

### 1. What our bot does

- We do **not** call `sendChatAction` or any other API when we receive the message.
- The **only** outbound Bot API call we make before the final `ctx.reply()` is **`sendMessageDraft`**.
- We send the first draft only after we have at least `MIN_FIRST_DRAFT_CHARS` (50) from the OpenAI stream and our throttle allows it. So the first `sendMessageDraft` happens some time after the user sent (typically a few hundred ms to ~1s: network to OpenAI + first tokens + 50 chars).

### 2. What happens on the client when we send a draft

When we call `sendMessageDraft(chatId, draftId, text, replyOptions)`:

1. Telegram's servers receive the call and update the **draft state** for that chat/thread.
2. Telegram then **pushes that draft state** to the user's client (the Telegram app).
3. The client receives the push and must **update the UI**:
   - It inserts or updates a **draft row** in the thread's message list (the bot's reply-in-progress).
   - It **reflows** the list: recomputes layout, heights, scroll position.
   - It may scroll so the draft is visible.

So the **only** server→client event that can change the thread view before the final reply is this **draft update**.

### 3. Why the user's message disappears

The user's message is **not** a draft. It is a normal, already-sent message. The draft is only the bot's reply.

The disappearance happens because of **when** the client applies the draft update relative to **when** it has finished rendering the user's sent message:

- **Race:** When the user hits "send", the client often shows the message **optimistically** (moves it from input to the list) and may still be in the process of "committing" it (e.g. waiting for server confirmation, or doing a layout pass). The client's list is in a **transitional state**.
- **Trigger:** Our first draft update arrives (Telegram pushes it). The client's handler runs: "add/update draft row → reflow list."
- **Effect:** That reflow runs **before** (or in the same cycle as) the client fully stabilizing the user's message in the list. So:
  - The list is rebuilt or re-sorted with the new draft row.
  - The node that was showing the user's message is **temporarily unmounted**, **scrolled out of view**, or **re-rendered with a delay**.
  - The user sees their message "disappear" and then "reappear" when the next layout or update paints it again.

So the **exact reason** is:

**The client's handling of the first incoming draft update (from our first `sendMessageDraft`) causes it to insert/update the draft row and reflow the thread's message list. That reflow happens so soon after the user sent that the client has not yet (or no longer) fully committed the user's message in the list. The reflow therefore temporarily removes or hides the user's message from the visible DOM or viewport; it reappears when the client finishes applying both the user's message and the draft.**

In short: **the first draft update triggers a list reflow that races with the client's "message sent" UI, so the user's message is briefly not visible.**

### 4. Why it's more visible in threads

In a thread, the list is scoped to that topic. Adding a new row (the draft) is a larger relative change and more likely to trigger a full reflow or scroll adjustment. In a simple private chat the same reflow can be less noticeable.

### 5. What we can do (and what we did)

We **cannot** change the Telegram client. We can only change **when** we send the first draft:

- **Content-based gate:** We do not send the first draft until we have at least `MIN_FIRST_DRAFT_CHARS` (50) of response text. So the first draft is not a single character or word; it's a real chunk. That pushes the first draft update **later**, giving the client more time to commit the user's message before the reflow. We do **not** use a blind time delay.
- **Optional:** Increase `MIN_FIRST_DRAFT_CHARS` (e.g. to 80–100) to send the first draft even later if the issue persists.

The trigger remains: **first draft update → client reflow → user message temporarily hidden.** The mitigation is: **send the first draft a bit later (more content) so the reflow happens after the client has stabilized the user's message.**
