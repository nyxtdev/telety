//go:build !js && (!telety_tdlib || (!darwin && !android))

package telegram

import "time"

type stubClient struct{}

func NewClient() TelegramClient                              { return stubClient{} }
func (stubClient) Available() bool                           { return false }
func (stubClient) Close() error                              { return nil }
func (stubClient) SendJSON(string) error                     { return ErrUnavailable }
func (stubClient) ReceiveJSON(time.Duration) (string, error) { return "", ErrUnavailable }
func (stubClient) ExecuteJSON(string) (string, error)        { return "", ErrUnavailable }
