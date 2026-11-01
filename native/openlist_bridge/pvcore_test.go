package pvcore

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/OpenListTeam/OpenList/v4/internal/op"
)

// Real pinned core in a fresh macOS test process. This is not Android JNI evidence.
func TestOneShotLocalCore(t *testing.T) {
	sample, err := os.ReadFile(os.Getenv("PV_W01_FIXTURE_PATH"))
	if err != nil || len(sample) != 14415 {
		t.Fatal("fixture unavailable")
	}
	directory := t.TempDir()
	if err := os.Mkdir(filepath.Join(directory, "fixture"), 0700); err != nil {
		t.Fatal("fixture directory")
	}
	if err := os.WriteFile(filepath.Join(directory, "fixture", "样本.png"), sample, 0600); err != nil {
		t.Fatal("fixture copy")
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal("local listener unavailable")
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	private, err := Start(directory, int64(port))
	if err != nil {
		t.Fatal("native initialization failed")
	}
	defer Stop()
	allowed := map[string]bool{"Local": true, "BaiduNetdisk": true, "Crypt": true}
	if len(op.GetDriverNames()) != len(allowed) {
		t.Fatal("runtime driver set exceeds W01 allowlist")
	}
	for _, name := range op.GetDriverNames() {
		if !allowed[name] {
			t.Fatal("runtime driver outside W01 allowlist")
		}
	}
	credentials := map[string]string{}
	if json.Unmarshal([]byte(private), &credentials) != nil {
		t.Fatal("native result invalid")
	}
	if credentials["buildId"] != BuildID() || credentials["baseUrl"] != "http://127.0.0.1:"+strconv.Itoa(port) {
		t.Fatal("identity mismatch")
	}
	base := credentials["baseUrl"]
	client := &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{DisableKeepAlives: true},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	request := func(path string, body any, token string) (int, []byte, error) {
		method := "GET"
		var input io.Reader
		if body != nil {
			method = "POST"
			encoded, _ := json.Marshal(body)
			input = bytes.NewReader(encoded)
		}
		req, _ := http.NewRequest(method, base+path, input)
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}
		if token != "" {
			req.Header.Set("Authorization", token)
		}
		response, err := client.Do(req)
		if err != nil {
			return 0, nil, err
		}
		defer response.Body.Close()
		content, err := io.ReadAll(io.LimitReader(response.Body, 96*1024+1))
		return response.StatusCode, content, err
	}
	ready := false
	for deadline := time.Now().Add(30 * time.Second); time.Now().Before(deadline); {
		status, content, err := request("/api/public/settings", nil, "")
		if err == nil && status == 200 && bytes.Contains(content, []byte("v4.2.8")) {
			ready = true
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if !ready {
		t.Fatal("core not ready")
	}
	_, login, err := request("/api/auth/login", map[string]string{"username": credentials["username"], "password": credentials["password"]}, "")
	if err != nil {
		t.Fatal("login request failed")
	}
	var auth struct {
		Code int
		Data struct{ Token string }
	}
	if json.Unmarshal(login, &auth) != nil || auth.Code != 200 || auth.Data.Token == "" {
		t.Fatal("private authentication failed")
	}
	parts := strings.Split(auth.Data.Token, ".")
	if len(parts) != 3 || len(credentials["serverKey"]) != 64 {
		t.Fatal("native identity proof missing")
	}
	signature, decodeErr := base64.RawURLEncoding.DecodeString(parts[2])
	proof := hmac.New(sha256.New, []byte(credentials["serverKey"]))
	proof.Write([]byte(parts[0] + "." + parts[1]))
	if decodeErr != nil || !hmac.Equal(proof.Sum(nil), signature) {
		t.Fatal("core instance token signature mismatch")
	}
	listBody := map[string]any{"path": "/w01", "password": "", "refresh": true, "page": 1, "per_page": 10}
	for _, check := range []struct {
		path string
		body any
	}{{"/api/fs/list", listBody}, {"/api/admin/user/list", nil}} {
		_, response, err := request(check.path, check.body, "")
		var denied struct{ Code int }
		if err != nil || json.Unmarshal(response, &denied) != nil || (denied.Code != 401 && denied.Code != 403) {
			t.Fatal("unauthenticated API was not denied")
		}
	}
	status, _, err := request("/p/w01/%E6%A0%B7%E6%9C%AC.png", nil, "")
	if err != nil || (status != 401 && status != 403) {
		t.Fatal("unsigned fixture was not denied")
	}
	_, listing, err := request("/api/fs/list", listBody, auth.Data.Token)
	var listed struct {
		Code int
		Data struct {
			Content []struct {
				Name string
				Size int
			}
		}
	}
	if err != nil || json.Unmarshal(listing, &listed) != nil || listed.Code != 200 || len(listed.Data.Content) != 1 || listed.Data.Content[0].Name != "样本.png" || listed.Data.Content[0].Size != len(sample) {
		t.Fatal("fixture listing mismatch")
	}
	_, info, err := request("/api/fs/get", map[string]string{"path": "/w01/样本.png", "password": ""}, auth.Data.Token)
	var file struct {
		Code int
		Data struct{ Sign string }
	}
	if err != nil || json.Unmarshal(info, &file) != nil || file.Code != 200 || file.Data.Sign == "" {
		t.Fatal("fixture capability invalid")
	}
	status, actual, err := request("/p/w01/%E6%A0%B7%E6%9C%AC.png?sign="+url.QueryEscape(file.Data.Sign), nil, "")
	if err != nil || status != 200 || !bytes.Equal(actual, sample) {
		t.Fatal("full fixture read mismatch")
	}
	Stop()
	if connection, err := net.DialTimeout("tcp4", "127.0.0.1:"+strconv.Itoa(port), time.Second); err == nil {
		connection.Close()
		t.Fatal("listener survived stop")
	}
	if _, err := Start(directory, int64(port)); err == nil {
		t.Fatal("same-process reinitialization accepted")
	}
}
