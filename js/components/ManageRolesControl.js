import { escapeHtml } from "../utils/escapeHtml.js";
import { ROLE_LABELS } from "../services/communityRecognition.js";
import { grantRole, revokeRole } from "../repositories/communityRepository.js";
import { confirmDialog } from "../utils/modal.js";
import { showToast } from "../core/toast.js";

// Milestone 22 §5.3/§8.1/§13 phase 5 — "a minimal grant action reachable
// only by an existing Staff account," no dedicated moderation dashboard
// yet. Deliberately placed in-context on the profile being reviewed
// (where a moderator/staff member is already looking when they decide
// someone deserves recognition) rather than a separate admin page. Every
// permission check here is a UX convenience only — grant_profile_role()/
// revoke_profile_role() (0028_moderation.sql) are the actual security
// boundary regardless of what this renders.
const MODERATOR_GRANTABLE = ["community_builder", "project_mentor"];
const STAFF_ONLY_GRANTABLE = ["moderator", "staff"];

export function renderManageRoles(container, { targetUserId, currentManualRoles, viewerIsStaff, onChange }) {
    if (!container) return;

    const grantable = [
        ...MODERATOR_GRANTABLE,
        ...(viewerIsStaff ? STAFF_ONLY_GRANTABLE : [])
    ].filter(role => !currentManualRoles.includes(role));

    container.innerHTML = `
        <p class="manage-roles-label">Manage roles</p>
        <div class="manage-roles-current">
            ${currentManualRoles.length
                ? currentManualRoles.map(role => `
                    <span class="badge role-badge manage-roles-item">
                        ${escapeHtml(ROLE_LABELS[role] || role)}
                        <button
                            type="button"
                            class="manage-roles-revoke"
                            data-role="${escapeHtml(role)}"
                            aria-label="Revoke ${escapeHtml(ROLE_LABELS[role] || role)}"
                        >${"×"}</button>
                    </span>
                `).join("")
                : `<span class="text-muted manage-roles-empty">No manually-granted roles.</span>`}
        </div>
        ${grantable.length ? `
            <div class="manage-roles-grant">
                <label for="manageRolesSelect" class="sr-only">Role to grant</label>
                <select id="manageRolesSelect">
                    ${grantable.map(role => `<option value="${escapeHtml(role)}">${escapeHtml(ROLE_LABELS[role])}</option>`).join("")}
                </select>
                <button type="button" class="btn btn-secondary btn-small" id="manageRolesGrantBtn">Grant</button>
            </div>
        ` : ""}
    `;

    container.querySelectorAll(".manage-roles-revoke").forEach(button => {
        button.addEventListener("click", async () => {
            const role = button.dataset.role;
            const label = ROLE_LABELS[role] || role;

            const confirmed = await confirmDialog({
                title: `Revoke ${label}?`,
                body: `This removes the ${label} role from this builder.`,
                confirmLabel: "Revoke",
                danger: true
            });

            if (!confirmed) return;

            try {
                await revokeRole(targetUserId, role);
                showToast(`${label} revoked.`, "success");
                onChange?.();
            } catch (error) {
                console.error("Revoke role error:", error);
                showToast(error.message || "Could not revoke role.", "error");
            }
        });
    });

    const grantBtn = container.querySelector("#manageRolesGrantBtn");

    grantBtn?.addEventListener("click", async () => {
        const role = container.querySelector("#manageRolesSelect")?.value;
        if (!role) return;

        grantBtn.disabled = true;

        try {
            await grantRole(targetUserId, role);
            showToast(`${ROLE_LABELS[role] || role} granted.`, "success");
            onChange?.();
        } catch (error) {
            console.error("Grant role error:", error);
            showToast(error.message || "Could not grant role.", "error");
        } finally {
            grantBtn.disabled = false;
        }
    });
}
