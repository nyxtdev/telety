//go:build telety_tdlib && (darwin || android)

package telegram

/*
#include <stdlib.h>
#include <td/telegram/td_json_client.h>
*/
import "C"

import (
	"errors"
	"sync"
	"time"
	"unsafe"
)

type nativeClient struct {
	mu     sync.Mutex
	handle unsafe.Pointer
}

func NewClient() TelegramClient {
	return &nativeClient{handle: C.td_json_client_create()}
}

func (client *nativeClient) Available() bool { return client.handle != nil }

func (client *nativeClient) Close() error {
	client.mu.Lock()
	defer client.mu.Unlock()
	if client.handle != nil {
		C.td_json_client_destroy(client.handle)
		client.handle = nil
	}
	return nil
}

func (client *nativeClient) SendJSON(request string) error {
	client.mu.Lock()
	defer client.mu.Unlock()
	if client.handle == nil {
		return ErrUnavailable
	}
	if request == "" {
		return errors.New("telegram request must not be empty")
	}

	cRequest := C.CString(request)
	defer C.free(unsafe.Pointer(cRequest))
	C.td_json_client_send(client.handle, cRequest)
	return nil
}

func (client *nativeClient) ReceiveJSON(timeout time.Duration) (string, error) {
	client.mu.Lock()
	defer client.mu.Unlock()
	if client.handle == nil {
		return "", ErrUnavailable
	}
	if timeout < 0 {
		return "", errors.New("telegram receive timeout must not be negative")
	}

	response := C.td_json_client_receive(client.handle, C.double(timeout.Seconds()))
	if response == nil {
		return "", nil
	}
	return C.GoString(response), nil
}

func (client *nativeClient) ExecuteJSON(request string) (string, error) {
	client.mu.Lock()
	defer client.mu.Unlock()
	if client.handle == nil {
		return "", ErrUnavailable
	}
	if request == "" {
		return "", errors.New("telegram request must not be empty")
	}

	cRequest := C.CString(request)
	defer C.free(unsafe.Pointer(cRequest))
	response := C.td_json_client_execute(client.handle, cRequest)
	if response == nil {
		return "", nil
	}
	return C.GoString(response), nil
}
