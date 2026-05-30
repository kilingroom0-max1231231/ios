(function () {
    "use strict";

    // ---- Footer year ----
    var yearEl = document.getElementById("year");
    if (yearEl) yearEl.textContent = new Date().getFullYear();

    // ---- Nav scroll state ----
    var nav = document.getElementById("nav");
    function onScroll() {
        if (!nav) return;
        nav.classList.toggle("scrolled", window.scrollY > 16);
    }
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();

    // ---- Mobile menu ----
    var menuBtn = document.getElementById("menu-btn");
    var mobileMenu = document.getElementById("mobile-menu");
    if (menuBtn && mobileMenu) {
        menuBtn.addEventListener("click", function () {
            mobileMenu.classList.toggle("hidden");
        });
        mobileMenu.querySelectorAll("a").forEach(function (a) {
            a.addEventListener("click", function () {
                mobileMenu.classList.add("hidden");
            });
        });
    }

    // ---- FAQ accordion ----
    document.querySelectorAll(".faq-q").forEach(function (btn) {
        btn.addEventListener("click", function () {
            var answer = btn.nextElementSibling;
            var icon = btn.querySelector(".faq-icon");
            var open = answer.classList.toggle("open");
            if (icon) icon.classList.toggle("open", open);
        });
    });

    // ---- Scroll reveal ----
    var revealEls = document.querySelectorAll(".reveal");
    if ("IntersectionObserver" in window) {
        var io = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) {
                    entry.target.classList.add("is-visible");
                    io.unobserve(entry.target);
                }
            });
        }, { threshold: 0.12 });
        revealEls.forEach(function (el) { io.observe(el); });
    } else {
        revealEls.forEach(function (el) { el.classList.add("is-visible"); });
    }

    // ---- Language toggle (RU <-> EN) ----
    var EN = {
        nav_features: "Features", nav_preview: "Interface", nav_download: "Install",
        nav_faq: "FAQ", nav_cta: "Download",
        hero_badge: "iOS 26 design · Liquid Glass",
        hero_title_1: "Your Telegram.", hero_title_2: "Only prettier.",
        hero_sub: "An unofficial Telegram client for iOS — a glassy interface, reactions, chat folders and blazing speed even on huge accounts.",
        hero_cta: "Download for iOS", hero_cta2: "Learn more",
        stat_native: "native SwiftUI", stat_engine: "official engine", stat_price: "free",
        features_title: "Everything you need. Nothing you don't.",
        features_sub: "Every detail rebuilt after the official client — and polished to a shine.",
        feature_1_title: "Liquid Glass design",
        feature_1_desc: "Native iOS 26 interface with frosted panels, fluid animations and a deep dark theme.",
        feature_2_title: "Blazing fast",
        feature_2_desc: "Lazy chat loading, caching and serialized TDLib requests — even on huge accounts.",
        feature_3_title: "Reactions & emoji",
        feature_3_desc: "Multi-reactions, custom premium emoji, long-press and double-tap quick reactions.",
        feature_4_title: "Folders & filters",
        feature_4_desc: "Full chat-folder support with tabs, just like the official client.",
        feature_5_title: "Tappable links",
        feature_5_desc: "Links, @mentions and t.me invites open right inside the app.",
        feature_6_title: "Privacy first",
        feature_6_desc: "Your data stays on-device. Direct connection to Telegram servers via TDLib.",
        preview_title: "An interface that feels native",
        preview_sub: "Frosted panels, live long-press reaction menus, smooth transitions and a dark theme — all in the spirit of iOS 26.",
        preview_b1: "Chat folders with tabs",
        preview_b2: "Custom premium emoji and reactions",
        preview_b3: "Stories, video notes and media",
        preview_b4: "Tappable links and @mentions",
        card_chats: "Chats", card_chats_sub: "instant search",
        card_reactions: "Reactions", card_reactions_sub: "long press",
        card_folders: "Folders", card_folders_sub: "with tabs",
        card_speed: "Speed", card_speed_sub: "no lag",
        dl_title: "Install in a couple of minutes",
        dl_sub: "The client ships as an IPA for sideloading via AltStore or SideStore.",
        dl_s1_t: "Install AltStore", dl_s1_d: "Set up AltStore / SideStore on your iPhone and Mac/PC.",
        dl_s2_t: "Download the IPA", dl_s2_d: "Grab the latest build from the GitHub releases.",
        dl_s3_t: "Open via AltStore", dl_s3_d: "Sideload the IPA and sign in to your Telegram account.",
        dl_btn: "Download IPA", dl_altstore: "What is AltStore?",
        faq_title: "Frequently asked questions",
        faq_1_q: "Is this the official Telegram app?",
        faq_1_a: "No. It's an independent client built on the open-source TDLib library using the official Telegram API.",
        faq_2_q: "How do I install without the App Store?",
        faq_2_a: "The build ships as an unsigned IPA for AltStore / SideStore. Download the IPA and sideload it via AltStore.",
        faq_3_q: "Is it safe to log in?",
        faq_3_a: "Authorization goes straight through Telegram servers (TDLib). Session and cache are stored locally on your device.",
        footer_about: "An unofficial Telegram client for iOS built on TDLib. Not affiliated with Telegram Messenger Inc.",
        footer_product: "Product", footer_legal: "Legal", footer_privacy: "Privacy",
        footer_rights: "All rights reserved.",
        back: "Back home",
        pp_title: "Privacy Policy", pp_updated: "Updated: 2026",
        pp_h1: "What data we collect",
        pp_p1: "Mase Telegram does not collect or send your personal data to third-party servers. Authorization and messaging happen directly with Telegram servers via the TDLib library.",
        pp_h2: "Data storage",
        pp_p2: "Your session, chat cache and media are stored locally on your device and never leave it, except for the exchange with the official Telegram API.",
        pp_h3: "Disclaimer",
        pp_p3: "This is an unofficial app, not affiliated with Telegram Messenger Inc. By using it you agree to the Telegram API terms of use."
    };

    var langBtn = document.getElementById("lang-toggle");
    var current = "ru";

    function applyLang(lang) {
        document.querySelectorAll("[data-i18n]").forEach(function (el) {
            var key = el.getAttribute("data-i18n");
            if (lang === "ru") {
                if (el.dataset.ru !== undefined) el.textContent = el.dataset.ru;
            } else if (EN[key] !== undefined) {
                if (el.dataset.ru === undefined) el.dataset.ru = el.textContent;
                el.textContent = EN[key];
            }
        });
        document.documentElement.lang = lang;
        if (langBtn) langBtn.textContent = lang === "ru" ? "EN" : "RU";
        try { localStorage.setItem("lang", lang); } catch (e) {}
        current = lang;
    }

    if (langBtn) {
        langBtn.addEventListener("click", function () {
            applyLang(current === "ru" ? "en" : "ru");
        });
    }

    var saved;
    try { saved = localStorage.getItem("lang"); } catch (e) {}
    if (saved === "en") applyLang("en");
})();
