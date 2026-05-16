import flet as ft

def main(page: ft.Page):
    page.title = "Hello World"

    texto = ft.Text("Hello World!", size=40)

    def cambiar(e):
        texto.value = "Hola Raspberry Pi 🚀"
        page.update()

    boton = ft.ElevatedButton(
        "Click",
        on_click=cambiar
    )

    page.add(texto, boton)

ft.app(target=main)
