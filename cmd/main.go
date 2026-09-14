package main

import (
	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
	"telety/internal/telegram"
)

func main() {
	a := app.New()
	w := a.NewWindow("My App")
	client := telegram.NewClient()
	defer client.Close()

	label := widget.NewLabel("Telegram client ready")

	w.SetContent(container.NewVBox(
		label,
		widget.NewButton("Click", func() {
			label.SetText("Clicked!")
		}),
	))

	w.Resize(fyne.NewSize(400, 700))
	w.ShowAndRun()
}
