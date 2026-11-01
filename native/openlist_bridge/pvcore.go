// PrivateVault-owned integration for OpenList v4.2.8. See README.md for provenance.
package pvcore

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	stdlog "log"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/OpenListTeam/OpenList/v4/cmd/flags"
	_ "github.com/OpenListTeam/OpenList/v4/drivers/baidu_netdisk"
	_ "github.com/OpenListTeam/OpenList/v4/drivers/crypt"
	_ "github.com/OpenListTeam/OpenList/v4/drivers/local"
	"github.com/OpenListTeam/OpenList/v4/internal/bootstrap"
	"github.com/OpenListTeam/OpenList/v4/internal/bootstrap/data"
	"github.com/OpenListTeam/OpenList/v4/internal/conf"
	"github.com/OpenListTeam/OpenList/v4/internal/db"
	"github.com/OpenListTeam/OpenList/v4/internal/model"
	"github.com/OpenListTeam/OpenList/v4/internal/op"
	"github.com/OpenListTeam/OpenList/v4/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

var mu sync.Mutex
var initialized, dbOpen, running bool
var buildIdentity = "unbuilt"

const fixtureDigest = "d70a3c38d62588d9a2b61b7f676fef022039df34c12c92bfade0129103005901"

func Version() string { return conf.Version }
func BuildID() string { return buildIdentity }

func secret() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", errors.New("entropy_unavailable")
	}
	return hex.EncodeToString(b), nil
}

// Start is called only in the private service process, once in its lifetime.
// The JSON result contains native-only credentials and must never cross to Dart.
func Start(directory string, port int64) (result string, err error) {
	mu.Lock()
	defer mu.Unlock()
	defer func() {
		if recover() != nil {
			result = ""
			err = errors.New("core_initialization_failed")
		}
	}()
	if initialized {
		return "", errors.New("fresh_service_process_required")
	}
	initialized = true
	if !filepath.IsAbs(directory) || port < 1024 || port > 65535 || buildIdentity == "unbuilt" || conf.Version != "v4.2.8" {
		return "", errors.New("invalid_native_inputs")
	}
	fixture, readErr := os.ReadFile(filepath.Join(directory, "fixture", "样本.png"))
	if readErr != nil || len(fixture) != 14415 {
		return "", errors.New("fixture_invalid")
	}
	hash := sha256.Sum256(fixture)
	if hex.EncodeToString(hash[:]) != fixtureDigest {
		return "", errors.New("fixture_invalid")
	}
	if !op.PrivateVaultLimitDrivers() {
		return "", errors.New("driver_allowlist_unavailable")
	}
	// Never forward upstream logs, credentials, configuration, or panic text.
	logrus.SetOutput(io.Discard)
	utils.Log.SetOutput(io.Discard)
	stdlog.SetOutput(io.Discard)
	if null, openErr := os.OpenFile(os.DevNull, os.O_WRONLY, 0); openErr == nil {
		os.Stdout, os.Stderr = null, null
	} else {
		return "", errors.New("private_logging_unavailable")
	}
	gin.SetMode(gin.ReleaseMode)
	flags.Debug, flags.Dev, flags.LogStd = false, false, false
	flags.DataDir = filepath.Join(directory, "data")
	if err := os.MkdirAll(flags.DataDir, 0700); err != nil {
		return "", errors.New("private_directory_unavailable")
	}
	// Every session uses a new directory. Never open or migrate an existing DB.
	configFile := filepath.Join(flags.DataDir, "config.json")
	if _, statErr := os.Stat(configFile); !os.IsNotExist(statErr) {
		return "", errors.New("fresh_directory_required")
	}
	config := conf.DefaultConfig(flags.DataDir)
	config.Force = true
	config.Scheme.Address = "127.0.0.1"
	config.Scheme.HttpPort, config.Scheme.HttpsPort = int(port), -1
	config.Log.Enable = false
	config.Cdn = ""
	config.TokenExpiresIn = 1
	config.S3.Enable, config.FTP.Enable, config.SFTP.Enable, config.MCP.Enable = false, false, false, false
	config.JwtSecret, err = secret()
	if err != nil {
		return "", err
	}
	password, err := secret()
	if err != nil {
		return "", err
	}
	encoded, marshalErr := json.Marshal(config)
	if marshalErr != nil {
		return "", errors.New("config_initialization_failed")
	}
	if err := os.WriteFile(configFile, encoded, 0600); err != nil {
		return "", errors.New("config_initialization_failed")
	}
	bootstrap.InitConfig()
	if err := os.Chmod(configFile, 0600); err != nil {
		return "", errors.New("config_permissions_failed")
	}
	bootstrap.InitDB()
	dbOpen = true
	admin := (&model.User{Username: "admin", BasePath: "/", Role: model.ADMIN, Permission: 0x71FF, Authn: "[]"}).SetPassword(password)
	if err := op.CreateUser(admin); err != nil {
		return "", errors.New("private_admin_failed")
	}
	data.InitData()
	bootstrap.InitStreamLimit()
	bootstrap.InitIndex()
	bootstrap.InitUpgradePatch()
	addition, _ := json.Marshal(map[string]any{"root_folder_path": filepath.Join(directory, "fixture"), "thumbnail": false, "show_hidden": false})
	storage := model.Storage{MountPath: "/w01", Driver: "Local", Addition: string(addition), EnableSign: true}
	storage.WebProxy = true
	if err := db.CreateStorage(&storage); err != nil {
		return "", errors.New("fixture_storage_failed")
	}
	bootstrap.Start()
	running = true
	privateResult, _ := json.Marshal(map[string]string{
		"baseUrl":  "http://127.0.0.1:" + strconv.FormatInt(port, 10),
		"username": "admin", "password": password, "buildId": buildIdentity,
		"serverKey": config.JwtSecret,
	})
	return string(privateResult), nil
}

// The caller must exit its own service process after this returns.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	if running {
		bootstrap.Shutdown(3 * time.Second)
		running = false
	}
	if dbOpen {
		bootstrap.Release()
		dbOpen = false
	}
}
