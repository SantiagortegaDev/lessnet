import flet as ft
import asyncio
from flet_permission_handler import PermissionHandler, Permission, PermissionStatus

async def main(page: ft.Page):
    # Configuración de la página para móviles
    page.title = "Permissions Manager"
    page.theme_mode = ft.ThemeMode.DARK
    page.padding = 0
    page.bgcolor = "#0F172A"  # Color de fondo premium (Slate 900)
    
    # Fuentes y estilo
    page.fonts = {
        "Outfit": "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit-VariableFont_wght.ttf"
    }
    page.theme = ft.Theme(
        font_family="Outfit",
        color_scheme_seed=ft.Colors.BLUE,
        visual_density=ft.VisualDensity.COMFORTABLE,
    )

    # Configuración de permisos
    perms_data = [
        {"id": "camera", "name": "Cámara", "icon": ft.Icons.CAMERA_ALT_ROUNDED, "type": "CAMERA"},
        {"id": "location", "name": "Ubicación", "icon": ft.Icons.LOCATION_ON_ROUNDED, "type": "LOCATION"},
        {"id": "mic", "name": "Micrófono", "icon": ft.Icons.MIC_ROUNDED, "type": "MICROPHONE"},
        {"id": "storage", "name": "Almacenamiento", "icon": ft.Icons.STORAGE_ROUNDED, "type": "STORAGE"},
    ]

    # Estado de los permisos (almacenamos los controles de la lista)
    permission_items = ft.Column(spacing=12, animate_opacity=300)

    # Permission Handler - Solo lo inicializamos si estamos en móvil
    # El PermissionHandler NO es un control visual, por eso NO debe añadirse al overlay
    ph = None
    is_mobile = page.platform in [ft.PagePlatform.IOS, ft.PagePlatform.ANDROID]
    
    if is_mobile:
        try:
            ph = PermissionHandler()
            # Actualizamos los tipos de permisos para usar el enum de Permission
            perms_data = [
                {"id": "camera", "name": "Cámara", "icon": ft.Icons.CAMERA_ALT_ROUNDED, "type": Permission.CAMERA},
                {"id": "location", "name": "Ubicación", "icon": ft.Icons.LOCATION_ON_ROUNDED, "type": Permission.LOCATION},
                {"id": "mic", "name": "Micrófono", "icon": ft.Icons.MIC_ROUNDED, "type": Permission.MICROPHONE},
                {"id": "storage", "name": "Almacenamiento", "icon": ft.Icons.STORAGE_ROUNDED, "type": Permission.STORAGE},
            ]
        except Exception as e:
            print(f"Error initializing PermissionHandler: {e}")
            ph = None

    def get_status_ui(status):
        """Devuelve el icono y color según el estado del permiso"""
        status_str = str(status).lower()
        if "granted" in status_str:
            return ft.Icon(ft.Icons.CHECK_CIRCLE_ROUNDED, color=ft.Colors.GREEN_400, size=24)
        elif "denied" in status_str:
            return ft.Icon(ft.Icons.CANCEL_ROUNDED, color=ft.Colors.RED_400, size=24)
        elif "permanently" in status_str:
            return ft.Icon(ft.Icons.BLOCK_ROUNDED, color=ft.Colors.RED_900, size=24)
        else:
            return ft.Icon(ft.Icons.HELP_OUTLINE_ROUNDED, color=ft.Colors.GREY_600, size=24)

    def get_status_text(status):
        """Devuelve el texto del estado del permiso"""
        status_str = str(status).split(".")[-1].replace("_", " ").capitalize()
        if "unknown" in status_str.lower(): status_str = "Pendiente"
        return status_str

    async def check_permission_status(p_type):
        """Verifica el estado de un permiso de forma segura"""
        if ph is None:
            return None
        try:
            status = await ph.get_status(p_type)
            return status
        except Exception as e:
            print(f"Error checking permission: {e}")
            return None

    async def update_permissions_status():
        """Actualiza la lista de permisos en la UI"""
        permission_items.controls.clear()
        for p in perms_data:
            # Verificamos el estado actual
            status = await check_permission_status(p["type"])
            status_str = get_status_text(status)
            
            permission_items.controls.append(
                ft.Container(
                    content=ft.Row(
                        [
                            ft.Container(
                                content=ft.Icon(p["icon"], color=ft.Colors.WHITE, size=20),
                                bgcolor=ft.Colors.BLUE_700,
                                padding=12,
                                border_radius=12,
                                shadow=ft.BoxShadow(blur_radius=10, color=ft.Colors.with_opacity(0.2, ft.Colors.BLUE_900)),
                            ),
                            ft.Column(
                                [
                                    ft.Text(p["name"], size=16, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
                                    ft.Text(status_str, size=12, color=ft.Colors.BLUE_200 if "Granted" in status_str else ft.Colors.GREY_400),
                                ],
                                spacing=2,
                                expand=True,
                            ),
                            get_status_ui(status),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    bgcolor=ft.Colors.with_opacity(0.05, ft.Colors.WHITE),
                    padding=16,
                    border_radius=20,
                    border=ft.border.Border(
                        ft.border.BorderSide(1, ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
                        ft.border.BorderSide(1, ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
                        ft.border.BorderSide(1, ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
                        ft.border.BorderSide(1, ft.Colors.with_opacity(0.1, ft.Colors.WHITE)),
                    ),
                    blur=ft.Blur(10, 10),
                )
            )
        page.update()

    async def request_all_permissions(e):
        """Solicita permisos uno por uno secuencialmente"""
        if ph is None:
            # En desktop, mostrar mensaje de que no hay permisos disponibles
            btn_request.content.value = "No disponible en desktop"
            page.update()
            await asyncio.sleep(2)
            btn_request.content.value = "Activar Permisos"
            page.update()
            return
            
        btn_request.disabled = True
        btn_request.content.value = "Solicitando..."
        progress_bar.visible = True
        page.update()

        for i, p in enumerate(perms_data):
            try:
                # Solicitamos el permiso actual usando la API correcta
                await ph.request(p["type"])
                # Actualizamos la UI inmediatamente después de cada respuesta
                await update_permissions_status()
                # Pequeña pausa para que el usuario vea el cambio
                await asyncio.sleep(0.5)
            except Exception as ex:
                print(f"Error requesting permission {p['id']}: {ex}")
            progress_bar.value = (i + 1) / len(perms_data)
            page.update()
        
        btn_request.disabled = False
        btn_request.content.value = "Permisos Completados"
        progress_bar.visible = False
        page.update()
        
        # Resetear texto después de 2 segundos
        await asyncio.sleep(2)
        btn_request.content.value = "Activar Permisos"
        page.update()

    async def refresh_all(e):
        """Efecto de rotación y actualización de estados"""
        refresh_icon.rotate = ft.Rotate(0)
        page.update()
        refresh_icon.rotate.angle += 6.28 # 360 grados
        page.update()
        
        # Simulamos una pequeña carga
        permission_items.opacity = 0.5
        page.update()
        await asyncio.sleep(0.6)
        
        await update_permissions_status()
        permission_items.opacity = 1
        page.update()

    # Componentes de UI
    refresh_icon = ft.IconButton(
        icon=ft.Icons.REFRESH_ROUNDED,
        icon_color=ft.Colors.BLUE_200,
        icon_size=28,
        on_click=refresh_all,
        rotate=ft.Rotate(0),
        animate_rotation=ft.Animation(600, ft.AnimationCurve.EASE_IN_OUT),
    )

    btn_request = ft.Button(
        content=ft.Text("Activar Permisos" if is_mobile else "Permisos no disponibles"),
        icon=ft.Icons.SHIELD_OUTLINED,
        on_click=request_all_permissions,
        disabled=not is_mobile,
        style=ft.ButtonStyle(
            color=ft.Colors.WHITE,
            bgcolor={"": ft.Colors.BLUE_600 if is_mobile else ft.Colors.GREY_700, "hovered": ft.Colors.BLUE_500 if is_mobile else ft.Colors.GREY_600},
            padding=22,
            shape=ft.RoundedRectangleBorder(radius=18),
            elevation={"pressed": 0, "": 5},
        ),
    )

    progress_bar = ft.ProgressBar(width=200, color=ft.Colors.BLUE_400, bgcolor=ft.Colors.BLUE_900, visible=False, border_radius=10)

    # Layout Principal
    # Usamos SafeArea para evitar que el contenido se oculte tras el notch o barra de estado
    content_layout = ft.Column(
        [
            # Header
            ft.Row(
                [
                    ft.Column(
                        [
                            ft.Text("Hello World", size=32, weight=ft.FontWeight.W_800, color=ft.Colors.WHITE),
                            ft.Text("Configuración Inicial", size=14, color=ft.Colors.BLUE_200),
                        ],
                        spacing=0,
                    ),
                    refresh_icon,
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
            ),
            
            ft.Container(height=30),
            
            # Sección de Permisos
            ft.Text("ESTADO DEL SISTEMA", size=12, weight=ft.FontWeight.W_600, color=ft.Colors.BLUE_400),
            ft.Container(height=10),
            permission_items,
            
            ft.Container(height=40, expand=True), # Empuja el botón hacia abajo
            
            # Footer / Botón de acción
            ft.Column(
                [
                    progress_bar,
                    ft.Container(height=10),
                    btn_request,
                ],
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            ft.Container(height=20),
        ],
        scroll=ft.ScrollMode.ADAPTIVE,
        expand=True,
    )

    # Contenedor principal con padding y SafeArea
    page.add(
        ft.SafeArea(
            content=ft.Container(
                content=content_layout,
                padding=20,
                expand=True,
            ),
            expand=True,
        )
    )

    # Carga inicial de estados
    await update_permissions_status()

# Ejecución de la app
if __name__ == "__main__":
    ft.run(main)
