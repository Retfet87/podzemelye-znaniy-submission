BACK_LABEL = "⬅️ Назад"


MAIN_MENU_PAYLOADS = frozenset({"nav:home", "hw:back", "community:back"})


def callback_button(text, payload):
    return {
        "type": "callback",
        "text": BACK_LABEL
        if text in ("Назад", "К списку", "К категориям", "К мероприятию")
        else text,
        "payload": payload,
    }


def is_redundant_back(button):
    return (
        button.get("text") == BACK_LABEL and button.get("payload") in MAIN_MENU_PAYLOADS
    )


def inline_keyboard(rows, *, home=True):
    
    rows = [list(row) for row in rows]
    if home:
        rows = [
            row
            for row in ([b for b in row if not is_redundant_back(b)] for row in rows)
            if row
        ]
    if home and not any(b.get("payload") == "nav:home" for row in rows for b in row):
        rows.append([callback_button("🏠 Домой", "nav:home")])
    return [{"type": "inline_keyboard", "payload": {"buttons": rows}}]


def vertical_keyboard(buttons, *, prefix=""):
    
    if not buttons:
        return []
    return inline_keyboard(
        [[callback_button(label[:70], prefix + payload)] for label, payload in buttons]
    )


def with_home(attachments):
    if any(a.get("type") == "inline_keyboard" for a in attachments or []):
        return attachments
    return list(attachments or []) + inline_keyboard([])
