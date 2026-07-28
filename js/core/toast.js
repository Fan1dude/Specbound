import { icon } from "../utils/icons.js";

export function showToast(message, type = "success", duration = 3500) {
    let container = document.getElementById("toastContainer");

    if (!container) {
        container = document.createElement("div");
        container.id = "toastContainer";
        container.className = "toast-container";
        container.setAttribute("role", "status");
        container.setAttribute("aria-live", "polite");
        document.body.appendChild(container);
    }

    const toast = document.createElement("div");
    toast.className = `toast ${type}`;

    toast.innerHTML = `
        <span class="toast-icon">${getIcon(type)}</span>
        <span class="toast-message"></span>
    `;

    toast.querySelector(".toast-message").textContent = message;

    container.appendChild(toast);

    requestAnimationFrame(() => {
        toast.classList.add("show");
    });

    setTimeout(() => {
        toast.classList.remove("show");

        setTimeout(() => {
            toast.remove();
        }, 300);
    }, duration);
}

function getIcon(type) {
    switch (type) {
        case "error":
            return icon("close", 20);
        case "warning":
            return icon("warning", 20);
        case "info":
            return icon("info", 20);
        default:
            return icon("check", 20);
    }
}