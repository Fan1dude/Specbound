import { requireAuth } from "../../core/auth.js";
import { renderMyFeedback } from "./renderMyFeedback.js";

// Milestone 26 — no role check, unlike loadFeedbackQueue.js. Any
// signed-in user reaches this page; RLS on feedback_submissions (self-
// read, unchanged since 0029) is what actually scopes the data, not a
// client-side check. requireAuth() redirects to login.html itself when
// signed out.
export async function loadMyFeedback() {
    const user = await requireAuth("../login.html");
    if (!user) return;

    await renderMyFeedback();
}
