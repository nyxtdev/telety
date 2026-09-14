package telegram

import (
	"errors"
	"time"
)

var ErrUnavailable = errors.New("telegram client is unavailable on this platform")

// TelegramClient is the application-facing Telegram transport.
// Native targets use TDLib; WebAssembly uses a backend-compatible stub.
type TelegramClient interface {
	Close() error
	Available() bool
	SendJSON(request string) error
	ReceiveJSON(timeout time.Duration) (string, error)
	ExecuteJSON(request string) (string, error)
}
