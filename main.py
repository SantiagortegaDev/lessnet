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

    # ──────────────────────────────────────────────
    # SNACKBAR
    # ──────────────────────────────────────────────
    def show_snack(msg: str, ok: bool = True):
        page.show_dialog(ft.SnackBar(
            ft.Text(msg, color=ft.Colors.WHITE),
            bgcolor=ft.Colors.BLUE_800 if ok else ft.Colors.RED_800,
        ))

    # ──────────────────────────────────────────────
    # PERMISOS
    # ──────────────────────────────────────────────
    perm_list = [
        {"key": "location",   "name": "Ubicación",  "type": fph.Permission.LOCATION,         "icon": ft.Icons.LOCATION_ON_ROUNDED,         "color": ft.Colors.ORANGE_400},
        {"key": "bt",         "name": "Bluetooth",  "type": fph.Permission.BLUETOOTH,         "icon": ft.Icons.BLUETOOTH_ROUNDED,           "color": ft.Colors.BLUE_400},
        {"key": "bt_scan",    "name": "BT Scan",    "type": fph.Permission.BLUETOOTH_SCAN,    "icon": ft.Icons.BLUETOOTH_SEARCHING_ROUNDED, "color": ft.Colors.CYAN_400},
        {"key": "bt_connect", "name": "BT Connect", "type": fph.Permission.BLUETOOTH_CONNECT, "icon": ft.Icons.BLUETOOTH_CONNECTED_ROUNDED, "color": ft.Colors.LIGHT_BLUE_400},
    ]

    status_texts = {}

    def make_perm_row(p):
        st = ft.Text("—", size=13, color=ft.Colors.GREY_500, weight=ft.FontWeight.W_600)
        status_texts[p["key"]] = st

        async def do_request(e, pt=p["type"], pk=p["key"], pn=p["name"]):
            if not is_mobile:
                show_snack("Solo funciona en el APK Android", ok=False)
                return
            try:
                result = await ph.request(pt)
                name = result.name if result else "unknown"
                granted = name == "granted"
                st.value = "✓ Concedido" if granted else "✗ Denegado"
                st.color = ft.Colors.GREEN_400 if granted else ft.Colors.RED_400
                page.update()
                show_snack(f"{pn}: {name}", ok=granted)
            except Exception as ex:
                show_snack(f"Error: {ex}", ok=False)

        return ft.Container(
            content=ft.Row(
                controls=[
                    ft.Container(
                        content=ft.Icon(p["icon"], color=p["color"], size=22),
                        bgcolor=ft.Colors.with_opacity(0.1, p["color"]),
                        padding=10,
                        border_radius=10,
                    ),
                    ft.Column(
                        controls=[
                            ft.Text(p["name"], size=15, color=ft.Colors.WHITE, weight=ft.FontWeight.W_500),
                            st,
                        ],
                        spacing=2,
                        expand=True,
                    ),
                    ft.FilledButton(
                        "Solicitar",
                        on_click=do_request,
                        style=ft.ButtonStyle(
                            bgcolor=ft.Colors.BLUE_700,
                            shape=ft.RoundedRectangleBorder(radius=8),
                        ),
                    ),
                ],
                spacing=10,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            bgcolor=ft.Colors.with_opacity(0.06, ft.Colors.WHITE),
            padding=14,
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
                st = status_texts.get(p["key"])
                if st:
                    st.value = "✓ Concedido" if granted else "✗ Denegado"
                    st.color = ft.Colors.GREEN_400 if granted else ft.Colors.RED_400
            except Exception:
                pass
        page.update()
        show_snack("Todos los permisos solicitados ✓")

    perms_view = ft.Column(
        controls=[
            ft.Text("Permisos Bluetooth", size=18, weight=ft.FontWeight.W_700, color=ft.Colors.WHITE),
            ft.Text("Necesarios para descubrir y conectar dispositivos", size=12, color=ft.Colors.BLUE_300),
            ft.Divider(color=ft.Colors.with_opacity(0.08, ft.Colors.WHITE)),
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
                content=ft.Row(
                    controls=[
                        ft.Icon(ft.Icons.INFO_OUTLINE_ROUNDED, color=ft.Colors.AMBER_400, size=16),
                        ft.Text(
                            "Los permisos solo funcionan en el APK instalado en Android.",
                            size=11, color=ft.Colors.AMBER_300, expand=True,
                        ),
                    ],
                    spacing=8,
                ),
                bgcolor=ft.Colors.with_opacity(0.12, ft.Colors.AMBER),
                padding=12,
                border_radius=10,
                visible=not is_mobile,
            ),
        ],
        spacing=12,
        scroll=ft.ScrollMode.ADAPTIVE,
        expand=True,
    )

    # ──────────────────────────────────────────────
    # CHAT
    # ──────────────────────────────────────────────
    messages_col = ft.Column(
        controls=[],
        spacing=8,
        scroll=ft.ScrollMode.ADAPTIVE,
        expand=True,
    )

    msg_input = ft.TextField(
        hint_text="Escribe un mensaje...",
        bgcolor=ft.Colors.with_opacity(0.08, ft.Colors.WHITE),
        border_color=ft.Colors.with_opacity(0.2, ft.Colors.WHITE),
        color=ft.Colors.WHITE,
        hint_style=ft.TextStyle(color=ft.Colors.GREY_500),
        expand=True,
        border_radius=12,
    )

    def add_bubble(sender: str, text: str, mine: bool = True):
        messages_col.controls.append(
            ft.Row(
                controls=[
                    ft.Container(
                        content=ft.Column(
                            controls=[
                                ft.Text(sender, size=10,
                                        color=ft.Colors.BLUE_300 if mine else ft.Colors.GREEN_300,
                                        weight=ft.FontWeight.W_600),
                                ft.Text(text, size=14, color=ft.Colors.WHITE),
                            ],
                            spacing=2,
                        ),
                        bgcolor=ft.Colors.BLUE_900 if mine else ft.Colors.with_opacity(0.12, ft.Colors.WHITE),
                        padding=12,
                        border_radius=12,
                        width=260,
                    ),
                ],
                alignment=ft.MainAxisAlignment.END if mine else ft.MainAxisAlignment.START,
            )
        )
        page.update()

    def send_msg(e):
        text = msg_input.value.strip()
        if not text:
            return
        msg_input.value = ""
        add_bubble("Tú", text, mine=True)
        # TODO: enviar por socket Bluetooth / WiFi Direct

    chat_view = ft.Column(
        controls=[
            ft.Text("Chat Local", size=18, weight=ft.FontWeight.W_700, color=ft.Colors.WHITE),
            ft.Text("Mensajes vía Bluetooth sin internet", size=12, color=ft.Colors.BLUE_300),
            ft.Divider(color=ft.Colors.with_opacity(0.08, ft.Colors.WHITE)),
            ft.Container(
                content=messages_col,
                expand=True,
                bgcolor=ft.Colors.with_opacity(0.04, ft.Colors.WHITE),
                border_radius=12,
                padding=12,
                height=380,
            ),
            ft.Row(
                controls=[
                    msg_input,
                    ft.IconButton(
                        icon=ft.Icons.SEND_ROUNDED,
                        icon_color=ft.Colors.BLUE_400,
                        on_click=send_msg,
                        style=ft.ButtonStyle(bgcolor=ft.Colors.BLUE_900),
                    ),
                ],
                spacing=8,
            ),
        ],
        spacing=12,
        expand=True,
    )

    # ──────────────────────────────────────────────
    # NAVEGACIÓN MANUAL (sin ft.Tabs — API cambió en v0.85)
    # ──────────────────────────────────────────────
    body = ft.Container(content=perms_view, expand=True)

    def nav_style(active: bool):
        return ft.ButtonStyle(
            bgcolor=ft.Colors.BLUE_800 if active else ft.Colors.with_opacity(0.06, ft.Colors.WHITE),
            color=ft.Colors.WHITE if active else ft.Colors.GREY_400,
            shape=ft.RoundedRectangleBorder(radius=10),
        )

    btn_perms = ft.FilledButton("Permisos", icon=ft.Icons.SHIELD_ROUNDED, style=nav_style(True), expand=True)
    btn_chat  = ft.FilledButton("Chat",     icon=ft.Icons.CHAT_ROUNDED,   style=nav_style(False), expand=True)

    def go_perms(e):
        body.content = perms_view
        btn_perms.style = nav_style(True)
        btn_chat.style  = nav_style(False)
        page.update()

    def go_chat(e):
        body.content = chat_view
        btn_perms.style = nav_style(False)
        btn_chat.style  = nav_style(True)
        page.update()

    btn_perms.on_click = go_perms
    btn_chat.on_click  = go_chat

    page.add(
        ft.SafeArea(
            content=ft.Container(
                content=ft.Column(
                    controls=[
                        ft.Row(
                            controls=[
                                ft.Icon(ft.Icons.HUB_ROUNDED, color=ft.Colors.BLUE_400, size=28),
                                ft.Text("LessNet", size=24, weight=ft.FontWeight.W_700, color=ft.Colors.WHITE),
                            ],
                            spacing=10,
                        ),
                        ft.Row(controls=[btn_perms, btn_chat], spacing=8),
                        ft.Divider(color=ft.Colors.with_opacity(0.08, ft.Colors.WHITE), height=16),
                        body,
                    ],
                    spacing=12,
                    expand=True,
                ),
                padding=16,
                expand=True,
            ),
            expand=True,
        )
    )


if __name__ == "__main__":
    ft.run(main)