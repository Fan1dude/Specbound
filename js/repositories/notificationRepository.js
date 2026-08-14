import { supabase } from "../core/supabase.js";
import { getProfilesByIds } from "./profileRepository.js";
import { getBuildsByIds } from "./buildRepository.js";

// RLS (see supabase/migrations/0011_notifications.sql) already scopes
// every read here to recipient_id = auth.uid() — a signed-out caller
// simply shouldn't call any of these.

export async function getUnreadNotificationCount() {
    const { count, error } = await supabase
        .from("notifications")
        .select("*", { count: "exact", head: true })
        .is("read_at", null);

    if (error) throw error;

    return count || 0;
}

export async function getRecentNotifications(limit = 8) {
    const { data, error } = await supabase
        .from("notifications")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (error) throw error;

    return data || [];
}

// Keyset pagination (not offset) — before is the created_at of the last
// row already loaded, so notifications arriving between page loads can't
// shift the results and cause skipped or duplicated rows the way offset
// pagination could.
export async function getNotificationsPage({ before = null, limit = 20 } = {}) {
    let query = supabase
        .from("notifications")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(limit);

    if (before) {
        query = query.lt("created_at", before);
    }

    const { data, error } = await query;

    if (error) throw error;

    return data || [];
}

export async function markNotificationRead(notificationId) {
    const { data, error } = await supabase.rpc("mark_notification_read", {
        p_notification_id: notificationId
    });

    if (error) throw error;

    return data;
}

export async function markAllNotificationsRead() {
    const { data, error } = await supabase.rpc("mark_all_notifications_read");

    if (error) throw error;

    return data || 0;
}

// Batch-attaches each notification's actor profile and target build in
// two queries total (not one per notification) — same no-FK, batch-fetch-
// then-map pattern as every other build/profile pairing in this app.
// Every notification's build is always visible to its own recipient (RLS
// builds SELECT already allows an owner to see their own build
// regardless of visibility), so unlike saved projects, no entry is ever
// silently dropped here.
export async function enrichNotifications(notifications) {
    if (!notifications.length) return [];

    // Milestone 26 — feedback_reviewed/feedback_closed notifications
    // always have actor_id null (a deliberate privacy requirement, see
    // supabase/migrations/0039_feedback_status_workflow.sql), the same
    // shape that already required filtering build_id below. Same reason:
    // getProfilesByIds() does an unfiltered .in("id", ids); a raw null
    // in that array reaches PostgREST as "id=in.(null)" and Postgres
    // rejects it as an invalid uuid.
    const uniqueActorIds = [...new Set(notifications.map(n => n.actor_id).filter(Boolean))];
    // report_resolved and follow notifications always have build_id null
    // (see notificationFormat.js) — getBuildsByIds() does an unfiltered
    // .in("id", ids), and PostgREST/Postgres reject a null in that list
    // ("invalid input syntax for type uuid: null"), so null must never
    // reach it.
    const uniqueBuildIds = [...new Set(notifications.map(n => n.build_id).filter(Boolean))];

    const [profiles, builds] = await Promise.all([
        getProfilesByIds(uniqueActorIds),
        getBuildsByIds(uniqueBuildIds)
    ]);

    const profilesById = new Map(profiles.map(profile => [profile.id, profile]));
    const buildsById = new Map(builds.map(build => [build.id, build]));

    return notifications.map(notification => ({
        ...notification,
        actor: profilesById.get(notification.actor_id) || null,
        build: buildsById.get(notification.build_id) || null
    }));
}
