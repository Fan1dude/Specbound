import { requireAuth } from "../../core/auth.js";
import { renderNotifications } from "./renderNotifications.js";

export async function loadNotifications() {
    const user = await requireAuth("login.html");

    if (!user) return;

    await renderNotifications();
}
