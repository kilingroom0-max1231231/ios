"""Marketing/landing site for the iOS Telegram user client.

Run locally:
    pip install -r requirements.txt
    python app.py
Then open http://127.0.0.1:5000
"""
from __future__ import annotations

from flask import Flask, render_template, jsonify

app = Flask(__name__)

# Single source of truth for the content shown across the site.
APP_NAME = "Mase Telegram"
APP_TAGLINE = {
    "ru": "Неофициальный Telegram-клиент для iOS",
    "en": "An unofficial Telegram client for iOS",
}

FEATURES = [
    {
        "icon": "sparkles",
        "title": {"ru": "Liquid Glass дизайн", "en": "Liquid Glass design"},
        "desc": {
            "ru": "Нативный интерфейс iOS 26 со стеклянными панелями, плавными анимациями и тёмной темой.",
            "en": "Native iOS 26 interface with frosted panels, fluid animations and a deep dark theme.",
        },
    },
    {
        "icon": "bolt",
        "title": {"ru": "Молниеносная скорость", "en": "Blazing fast"},
        "desc": {
            "ru": "Ленивая загрузка чатов, кэширование и сериализация запросов TDLib — даже на огромных аккаунтах.",
            "en": "Lazy chat loading, caching and serialized TDLib requests — even on huge accounts.",
        },
    },
    {
        "icon": "face-smile",
        "title": {"ru": "Реакции и эмодзи", "en": "Reactions & emoji"},
        "desc": {
            "ru": "Мульти-реакции, кастомные премиум-эмодзи, долгий тап и быстрые реакции двойным тапом.",
            "en": "Multi-reactions, custom premium emoji, long-press and double-tap quick reactions.",
        },
    },
    {
        "icon": "folder",
        "title": {"ru": "Папки и фильтры", "en": "Folders & filters"},
        "desc": {
            "ru": "Полная поддержка папок чатов с вкладками — как в официальном клиенте.",
            "en": "Full chat-folder support with tabs, just like the official client.",
        },
    },
    {
        "icon": "link",
        "title": {"ru": "Кликабельные ссылки", "en": "Tappable links"},
        "desc": {
            "ru": "Ссылки, @упоминания и приглашения t.me открываются прямо внутри приложения.",
            "en": "Links, @mentions and t.me invites open right inside the app.",
        },
    },
    {
        "icon": "shield-check",
        "title": {"ru": "Приватность", "en": "Privacy first"},
        "desc": {
            "ru": "Данные хранятся только на устройстве. Прямое подключение к серверам Telegram через TDLib.",
            "en": "Your data stays on-device. Direct connection to Telegram servers via TDLib.",
        },
    },
]

FAQ = [
    {
        "q": {"ru": "Это официальное приложение Telegram?", "en": "Is this the official Telegram app?"},
        "a": {
            "ru": "Нет. Это независимый клиент на базе открытой библиотеки TDLib. Он использует официальный API Telegram.",
            "en": "No. It's an independent client built on the open-source TDLib library using the official Telegram API.",
        },
    },
    {
        "q": {"ru": "Как установить без App Store?", "en": "How do I install without the App Store?"},
        "a": {
            "ru": "Сборка распространяется как unsigned IPA для AltStore / SideStore. Скачайте IPA и установите через AltStore.",
            "en": "The build ships as an unsigned IPA for AltStore / SideStore. Download the IPA and sideload it via AltStore.",
        },
    },
    {
        "q": {"ru": "Безопасно ли вводить номер?", "en": "Is it safe to log in?"},
        "a": {
            "ru": "Авторизация идёт напрямую через серверы Telegram (TDLib). Сессия и кэш хранятся локально на устройстве.",
            "en": "Authorization goes straight through Telegram servers (TDLib). Session and cache are stored locally on your device.",
        },
    },
]


@app.route("/")
def index():
    return render_template(
        "index.html",
        app_name=APP_NAME,
        tagline=APP_TAGLINE,
        features=FEATURES,
        faq=FAQ,
    )


@app.route("/privacy")
def privacy():
    return render_template("privacy.html", app_name=APP_NAME)


@app.route("/healthz")
def healthz():
    return jsonify(status="ok", app=APP_NAME)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
