import flet as ft
import flet_permission_handler as fph


def main(page: ft.Page):
    page.title = "LessNet - Permisos"
    page.theme_mode = ft.ThemeMode.DARK
    page.padding = 0
    page.bgcolor = "#0F172A"

    page.fonts = {
        "Outfit": "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit-VariableFont_wght.ttf"
    }
    page.theme = ft.Theme(
        font_family="Outfit",
        color_scheme_seed=ft.Colors.BLUE,
        visual_density=ft.VisualDensity.COMFORTABLE,
    )

    # ✅ Solo agregar PermissionHandler en plataformas compatibles
    is_mobile = page.platform in (ft.PagePlatform.ANDROID, ft.PagePlatform.IOS)
    ph = None

    if is_mobile:
      ph = fph.PermissionHandler()
      page.add(ph)  # ✅ directo a la página, no al overlay

    perms = [
        {
            "name": "Ubicación",
            "desc": "Requerida para WiFi Direct y Bluetooth scan",
            "icon": ft.Icons.LOCATION_ON_ROUNDED,
            "type": fph.Permission.LOCATION,
            "color": ft.Colors.ORANGE_400,
        },
        {
            "name": "Bluetooth",
            "desc": "Conexión básica entre dispositivos",
            "icon": ft.Icons.BLUETOOTH_ROUNDED,
            "type": fph.Permission.BLUETOOTH,
            "color": ft.Colors.BLUE_400,
        },
        {
            "name": "Bluetooth Scan",
            "desc": "Buscar dispositivos cercanos (Android 12+)",
            "icon": ft.Icons.BLUETOOTH_SEARCHING_ROUNDED,
            "type": fph.Permission.BLUETOOTH_SCAN,
            "color": ft.Colors.CYAN_400,
        },
        {
            "name": "Bluetooth Connect",
            "desc": "Conectarse a dispositivos emparejados (Android 12+)",
            "icon": ft.Icons.BLUETOOTH_CONNECTED_ROUNDED,
            "type": fph.Permission.BLUETOOTH_CONNECT,
            "color": ft.Colors.LIGHT_BLUE_400,
        },
        {
            "name": "Dispositivos WiFi Cercanos",
            "desc": "WiFi Direct / P2P sin internet (Android 13+)",
            "icon": ft.Icons.WIFI_ROUNDED,
            "type": fph.Permission.NEARBY_WIFI_DEVICES,
            "color": ft.Colors.GREEN_400,
        },
    ]

    def show_snackbar(message: str, error: bool = False):
        page.show_dialog(
            ft.SnackBar(
                ft.Text(message, color=ft.Colors.WHITE),
                bgcolor=ft.Colors.RED_800 if error else ft.Colors.BLUE_800,
            )
        )

    def make_card(p):
        perm_name = p["name"]
        perm_type = p["type"]
        perm_icon = p["icon"]
        perm_color = p["color"]
        perm_desc = p["desc"]

        status_text = ft.Text("—", size=12, color=ft.Colors.GREY_400, weight=ft.FontWeight.W_600)

        async def get_status(e, pt=perm_type, pn=perm_name):
            if not is_mobile:
                show_snackbar("Solo funciona en Android/iOS", error=True)
                return
            try:
                status = await ph.get_status(pt)
                status_name = status.name if status else "Desconocido"
                status_text.value = status_name
                status_text.color = ft.Colors.GREEN_400 if status_name == "granted" else ft.Colors.RED_400
                page.update()
                show_snackbar(f"{pn}: {status_name}")
            except Exception as ex:
                show_snackbar(f"Error: {ex}", error=True)

        async def request_perm(e, pt=perm_type, pn=perm_name):
            if not is_mobile:
                show_snackbar("Solo funciona en Android/iOS", error=True)
                return
            try:
                status = await ph.request(pt)
                status_name = status.name if status else "Desconocido"
                status_text.value = status_name
                status_text.color = ft.Colors.GREEN_400 if status_name == "granted" else ft.Colors.RED_400
                page.update()
                show_snackbar(f"{pn}: {status_name}")
            except Exception as ex:
                show_snackbar(f"Error: {ex}", error=True)

        return ft.Container(
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Container(
                                content=ft.Icon(perm_icon, color=perm_color, size=24),
                                bgcolor=ft.Colors.with_opacity(0.1, perm_color),
                                padding=10,
                                border_radius=12,
                            ),
                            ft.Column(
                                controls=[
                                    ft.Text(perm_name, size=16, weight=ft.FontWeight.W_600, color=ft.Colors.WHITE),
                                    ft.Text(perm_desc, size=11, color=ft.Colors.BLUE_200),
                                ],
                                spacing=2,
                                expand=True,
                            ),
                            status_text,
                        ],
                        spacing=12,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Row(
                        controls=[
                            ft.FilledButton(
                                "Solicitar",
                                icon=ft.Icons.LOCK_OPEN_ROUNDED,
                                on_click=request_perm,
                                style=ft.ButtonStyle(
                                    bgcolor=ft.Colors.BLUE_700,
                                    shape=ft.RoundedRectangleBorder(radius=10),
                                ),
                                expand=True,
                            ),
                            ft.OutlinedButton(
                                "Estado",
                                icon=ft.Icons.INFO_OUTLINE_ROUNDED,
                                on_click=get_status,
                                style=ft.ButtonStyle(
                                    color=ft.Colors.BLUE_200,
                                    shape=ft.RoundedRectangleBorder(radius=10),
                                ),
                                expand=True,
                            ),
                        ],
                        spacing=8,
                    ),
                ],
                spacing=12,
            ),
            bgcolor=ft.Colors.with_opacity(0.06, ft.Colors.WHITE),
            padding=16,
            border_radius=16,
            border=ft.Border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
        )

    async def solicitar_todos(e):
        if not is_mobile:
            show_snackbar("Solo funciona en Android/iOS", error=True)
            return
        for p in perms:
            try:
                await ph.request(p["type"])
            except Exception:
                pass
        show_snackbar("Todos los permisos solicitados ✓")

    async def open_settings(e):
        if not is_mobile:
            show_snackbar("Solo funciona en Android/iOS", error=True)
            return
        await ph.open_app_settings()

    # Banner de advertencia si estás en desktop
    desktop_banner = ft.Container(
        content=ft.Row(
            controls=[
                ft.Icon(ft.Icons.WARNING_AMBER_ROUNDED, color=ft.Colors.AMBER_400),
                ft.Text(
                    "Modo preview — los permisos solo funcionan en el APK instalado en Android",
                    size=12,
                    color=ft.Colors.AMBER_200,
                    expand=True,
                ),
            ],
            spacing=8,
        ),
        bgcolor=ft.Colors.with_opacity(0.15, ft.Colors.AMBER),
        padding=ft.padding.symmetric(horizontal=16, vertical=10),
        border_radius=10,
        border=ft.Border.all(1, ft.Colors.with_opacity(0.3, ft.Colors.AMBER)),
        visible=not is_mobile,
    )

    page.add(
        ft.SafeArea(
            content=ft.Container(
                content=ft.Column(
                    controls=[
                        ft.Row(
                            controls=[
                                ft.Icon(ft.Icons.HUB_ROUNDED, color=ft.Colors.BLUE_400, size=32),
                                ft.Column(
                                    controls=[
                                        ft.Text("LessNet", size=26, weight=ft.FontWeight.W_700, color=ft.Colors.WHITE),
                                        ft.Text("Permisos para red local", size=13, color=ft.Colors.BLUE_300),
                                    ],
                                    spacing=0,
                                ),
                            ],
                            spacing=12,
                        ),
                        desktop_banner,
                        ft.Divider(color=ft.Colors.with_opacity(0.1, ft.Colors.WHITE), height=24),
                        *[make_card(p) for p in perms],
                        ft.Container(height=8),
                        ft.FilledButton(
                            "Solicitar todos los permisos",
                            icon=ft.Icons.DONE_ALL_ROUNDED,
                            on_click=solicitar_todos,
                            style=ft.ButtonStyle(
                                bgcolor=ft.Colors.BLUE_600,
                                shape=ft.RoundedRectangleBorder(radius=12),
                            ),
                            width=float("inf"),
                        ),
                        ft.OutlinedButton(
                            "Abrir configuración de la app",
                            icon=ft.Icons.SETTINGS_ROUNDED,
                            on_click=open_settings,
                            style=ft.ButtonStyle(
                                color=ft.Colors.GREY_400,
                                shape=ft.RoundedRectangleBorder(radius=12),
                            ),
                            width=float("inf"),
                        ),
                    ],
                    scroll=ft.ScrollMode.ADAPTIVE,
                    spacing=12,
                ),
                padding=20,
                expand=True,
            ),
            expand=True,
        )
    )


if __name__ == "__main__":
    ft.run(main)