//go:build js && wasm

package telegram

import "time"

type webClient struct{}

func NewClient() TelegramClient                             { return webClient{} }
func (webClient) Available() bool                           { return false }
func (webClient) Close() error                              { return nil }
func (webClient) SendJSON(string) error                     { return ErrUnavailable }
func (webClient) ReceiveJSON(time.Duration) (string, error) { return "", ErrUnavailable }
func (webClient) ExecuteJSON(string) (string, error)        { return "", ErrUnavailable }
