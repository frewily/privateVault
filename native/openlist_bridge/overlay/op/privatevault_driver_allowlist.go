// PrivateVault-owned startup guard, overlaid into the pinned internal/op package.
package op

// PrivateVaultLimitDrivers runs once before HTTP/storage goroutines start.
// Upstream offline/search imports still compile other provider code; this guard
// limits the actual registry and does not pretend that code was compiled out.
func PrivateVaultLimitDrivers() bool {
	allowed := map[string]bool{"Local": true, "BaiduNetdisk": true, "Crypt": true}
	for name := range allowed {
		if _, exists := driverMap[name]; !exists {
			return false
		}
		if _, exists := driverInfoMap[name]; !exists {
			return false
		}
	}
	for name := range driverMap {
		if !allowed[name] {
			delete(driverMap, name)
		}
	}
	for name := range driverInfoMap {
		if !allowed[name] {
			delete(driverInfoMap, name)
		}
	}
	return true
}
