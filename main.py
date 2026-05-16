import flet as ft
import flet_permission_handler as fph

def main(page: ft.Page):
    page.title = "LessNet"
    page.theme_mode = ft.ThemeMode.DARK
    page.padding = 0
    page.bgcolor = "#0F172A"

    is_mobile = page.platform in (ft.PagePlatform.ANDROID, ft.PagePlatform.IOS)
    ph = None
    if is_mobile:
        ph = fph.PermissionHandler()
        page.add(ph)

    # --- Estado de permisos ---
    perms_granted = {
        "bt": False,
        "bt_scan": False,
        "bt_connect": False,
        "location": False,
    }

    perm_list = [
        {"key": "location",     "name": "Ubicación",         "type": fph.Permission.LOCATION,         "icon": ft.Icons.LOCATION_ON_ROUNDED,         "color": ft.Colors.ORANGE_400},
        {"key": "bt",           "name": "Bluetooth",         "type": fph.Permission.BLUETOOTH,         "icon": ft.Icons.BLUETOOTH_ROUNDED,           "color": ft.Colors.BLUE_400},
        {"key": "bt_scan",      "name": "BT Scan",           "type": fph.Permission.BLUETOOTH_SCAN,    "icon": ft.Icons.BLUETOOTH_SEARCHING_ROUNDED, "color": ft.Colors.CYAN_400},
        {"key": "bt_connect",   "name": "BT Connect",        "type": fph.Permission.BLUETOOTH_CONNECT, "icon": ft.Icons.BLUETOOTH_CONNECTED_ROUNDED, "color": ft.Colors.LIGHT_BLUE_400},
    ]

    def show_snack(msg: str, ok: bool = True):
        page.show_dialog(ft.SnackBar(
            ft.Text(msg, color=ft.Colors.WHITE),
            bgcolor=ft.Colors.BLUE_800 if ok else ft.Colors.RED_800,
        ))

    # --- Pantalla de permisos ---
    status_texts = {}

    def make_perm_row(p):
        st = ft.Text("—", size=12, color=ft.Colors.GREY_500, weight=ft.FontWeight.W_600)
        status_texts[p["key"]] = st

        async def do_request(e, pt=p["type"], pk=p["key"], pn=p["name"]):
            if not is_mobile:
                show_snack("Solo funciona en el APK Android", ok=False)
                return
            try:
                result = await ph.request(pt)
                name = result.name if result else "unknown"
                granted = name == "granted"
                perms_granted[pk] = granted
                st.value = "✓" if granted else "✗"
                st.color = ft.Colors.GREEN_400 if granted else ft.Colors.RED_400
                page.update()
                show_snack(f"{pn}: {name}", ok=granted)
            except Exception as ex:
                show_snack(f"Error: {ex}", ok=False)

        return ft.Container(
            content=ft.Row(controls=[
                ft.Container(
                    content=ft.Icon(p["icon"], color=p["color"], size=22),
                    bgcolor=ft.Colors.with_opacity(0.1, p["color"]),
                    padding=10, border_radius=10,
                ),
                ft.Text(p["name"], size=15, color=ft.Colors.WHITE, expand=True, weight=ft.FontWeight.W_500),
                st,
                ft.FilledButton(
                    "Solicitar",
                    on_click=do_request,
                    style=ft.ButtonStyle(
                        bgcolor=ft.Colors.BLUE_700,
                        shape=ft.RoundedRectangleBorder(radius=8),
                    ),
                ),
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            bgcolor=ft.Colors.with_opacity(0.06, ft.Colors.WHITE),
            padding=ft.Padding.symmetric(horizontal=14, vertical=12),
            border_radius=12,
            border=ft.Border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
        )

    async def solicitar_todos(e):
        if not is_mobile:
            show_snack("Solo funciona en el APK Android", ok=False)
            return
        for p in perm_list:
            try:
                result = await ph.request(p["type"])
                name = result.name if result else "unknown"
                granted = name == "granted"
                perms_granted[p["key"]] = granted
                if p["key"] in status_texts:
                    status_texts[p["key"]].value = "✓" if granted else "✗"
                    status_texts[p["key"]].color = ft.Colors.GREEN_400 if granted else ft.Colors.RED_400
            except Exception:
                pass
        page.update()
        show_snack("Permisos solicitados ✓")

    # --- Mensajería (simulada / preparada para socket) ---
    messages = []
    messages_col = ft.Column(controls=[], spacing=8, scroll=ft.ScrollMode.ADAPTIVE, expand=True)
    msg_input = ft.TextField(
        hint_text="Escribe un mensaje...",
        bgcolor=ft.Colors.with_opacity(0.08, ft.Colors.WHITE),
        border_color=ft.Colors.with_opacity(0.2, ft.Colors.WHITE),
        color=ft.Colors.WHITE,
        hint_style=ft.TextStyle(color=ft.Colors.GREY_500),
        expand=True,
        border_radius=12,
    )

    def add_message(sender: str, text: str, mine: bool = True):
        bubble = ft.Container(
            content=ft.Column(controls=[
                ft.Text(sender, size=10, color=ft.Colors.BLUE_300 if mine else ft.Colors.GREEN_300, weight=ft.FontWeight.W_600),
                ft.Text(text, size=14, color=ft.Colors.WHITE),
            ], spacing=2),
            bgcolor=ft.Colors.BLUE_900 if mine else ft.Colors.with_opacity(0.12, ft.Colors.WHITE),
            padding=ft.Padding.symmetric(horizontal=14, vertical=10),
            border_radius=ft.BorderRadius(
                top_left=12, top_right=12,
                bottom_left=4 if mine else 12,
                bottom_right=12 if mine else 4,
            ),
            alignment=ft.Alignment(1 if mine else -1, 0),
        )
        row = ft.Row(
            controls=[bubble],
            alignment=ft.MainAxisAlignment.END if mine else ft.MainAxisAlignment.START,
        )
        messages_col.controls.append(row)
        page.update()

    def send_msg(e):
        text = msg_input.value.strip()
        if not text:
            return
        msg_input.value = ""
        add_message("Tú", text, mine=True)
        # TODO: enviar vía socket Bluetooth / WiFi Direct
        # Por ahora simula respuesta
        page.update()

    # --- Tabs ---
    perms_tab = ft.Column(
        controls=[
            ft.Text("Permisos Bluetooth", size=18, weight=ft.FontWeight.W_700, color=ft.Colors.WHITE),
            ft.Text("Necesarios para descubrir y conectar dispositivos cercanos", size=12, color=ft.Colors.BLUE_300),
            ft.Divider(color=ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
            *[make_perm_row(p) for p in perm_list],
            ft.Container(height=4),
            ft.FilledButton(
                "Solicitar todos",
                icon=ft.Icons.DONE_ALL_ROUNDED,
                on_click=solicitar_todos,
                style=ft.ButtonStyle(
                    bgcolor=ft.Colors.BLUE_600,
                    shape=ft.RoundedRectangleBorder(radius=10),
                ),
                width=float("inf"),
            ),
            ft.Container(
                content=ft.Row(controls=[
                    ft.Icon(ft.Icons.INFO_OUTLINE_ROUNDED, color=ft.Colors.AMBER_400, size=16),
                    ft.Text(
                        "Los permisos solo funcionan en el APK instalado en Android.",
                        size=11, color=ft.Colors.AMBER_300, expand=True,
                    ),
                ], spacing=8),
                bgcolor=ft.Colors.with_opacity(0.12, ft.Colors.AMBER),
                padding=ft.Padding.symmetric(horizontal=12, vertical=10),
                border_radius=10,
                visible=not is_mobile,
            ),
        ],
        spacing=12,
        scroll=ft.ScrollMode.ADAPTIVE,
    )

    chat_tab = ft.Column(
        controls=[
            ft.Text("Chat Local", size=18, weight=ft.FontWeight.W_700, color=ft.Colors.WHITE),
            ft.Text("Mensajes entre dispositivos por Bluetooth (sin internet)", size=12, color=ft.Colors.BLUE_300),
            ft.Divider(color=ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
            ft.Container(
                content=messages_col,
                expand=True,
                bgcolor=ft.Colors.with_opacity(0.04, ft.Colors.WHITE),
                border_radius=12,
                padding=12,
                height=400,
            ),
            ft.Row(controls=[
                msg_input,
                ft.IconButton(
                    icon=ft.Icons.SEND_ROUNDED,
                    icon_color=ft.Colors.BLUE_400,
                    on_click=send_msg,
                    style=ft.ButtonStyle(bgcolor=ft.Colors.BLUE_900),
                ),
            ], spacing=8),
        ],
        spacing=12,
        expand=True,
    )

    tabs = ft.Tabs(
        selected_index=0,
        animation_duration=200,
        tabs=[
            ft.Tab(text="Permisos", icon=ft.Icons.SHIELD_ROUNDED, content=ft.Container(content=perms_tab, padding=ft.Padding.only(top=16))),
            ft.Tab(text="Chat", icon=ft.Icons.CHAT_ROUNDED, content=ft.Container(content=chat_tab, padding=ft.Padding.only(top=16))),
        ],
        expand=True,
    )

    page.add(
        ft.SafeArea(
            content=ft.Container(
                content=ft.Column(controls=[
                    ft.Row(controls=[
                        ft.Icon(ft.Icons.HUB_ROUNDED, color=ft.Colors.BLUE_400, size=28),
                        ft.Text("LessNet", size=24, weight=ft.FontWeight.W_700, color=ft.Colors.WHITE),
                    ], spacing=10),
                    ft.Divider(color=ft.Colors.with_opacity(0.1, ft.Colors.WHITE), height=16),
                    tabs,
                ], spacing=0, expand=True),
                padding=16,
                expand=True,
            ),
            expand=True,
        )
    )

if __name__ == "__main__":
    ft.run(main)