# SemaLink：编译并安装 HAP 到设备 A 与平板 B
# 一键编译并同时安装到 A、B

```powershell
$node = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$hdc = 'D:\Program Files\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'

$deviceA = '5KLBB25B07200367'
$deviceB = '5KLBB25B07200723'
$bundle = 'com.example.semalink'

& $node $hvigor --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  assembleHap

if ($LASTEXITCODE -ne 0) {
  throw 'HAP 编译失败，已停止安装'
}

$hap = Get-ChildItem .\entry\build -Recurse -Filter '*-signed.hap' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $hap -or -not (Test-Path $hap)) {
  throw '未找到已签名 HAP'
}

$targets = & $hdc list targets

if ($targets -notcontains $deviceA) {
  throw "未发现设备 A：$deviceA"
}

if ($targets -notcontains $deviceB) {
  throw "未发现平板 B：$deviceB"
}

Write-Host "正在安装到设备 A：$deviceA"
& $hdc -t $deviceA app install -r $hap

if ($LASTEXITCODE -ne 0) {
  throw '设备 A 安装失败'
}

Write-Host "正在安装到平板 B：$deviceB"
& $hdc -t $deviceB app install -r $hap

if ($LASTEXITCODE -ne 0) {
  throw '平板 B 安装失败'
}

Write-Host '两台设备安装完成。'
```
## 一、设备信息

### 设备 A

```text
设备 ID：5KLBB25B07200367
用途：可作为发起端或响应端
```

### 平板 B

```text
设备 ID：5KLBB25B07200723
用途：可作为发起端或响应端
```

### 应用信息

```text
项目目录：C:\Users\admin\DevEcoStudioProjects\SemaLink
Bundle Name：com.example.semalink
入口 Ability：EntryAbility
```

---

## 二、进入项目目录

```powershell
cd C:\Users\admin\DevEcoStudioProjects\SemaLink
```

---

## 三、配置工具和设备变量

```powershell
$node = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$hdc = 'D:\Program Files\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'

$deviceA = '5KLBB25B07200367'
$deviceB = '5KLBB25B07200723'

$bundle = 'com.example.semalink'
```

确认工具路径：

```powershell
Test-Path $node
Test-Path $hvigor
Test-Path $hdc
```

预期均返回：

```text
True
```

---

## 四、确认两台设备在线

```powershell
& $hdc list targets
```

预期包含：

```text
5KLBB25B07200367
5KLBB25B07200723
```

如果某台设备未显示，请检查：

- 是否开启开发者模式；
- 是否开启 USB 调试；
- 是否允许当前电脑调试；
- 数据线是否支持数据传输；
- HDC 是否被其他 DevEco Studio 实例占用。

---

## 五、编译并签名正式调试 HAP

```powershell
& $node $hvigor --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  assembleHap
```

编译成功时应看到：

```text
BUILD SUCCESSFUL
```

如果出现 `CompileArkTS`、`PackageHap` 或 `SignHap` 错误，应先解决错误，不要继续安装旧 HAP。

---

## 六、获取最新已签名 HAP

```powershell
$hap = Get-ChildItem .\entry\build -Recurse -Filter '*-signed.hap' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName

$hap
```

正常路径类似：

```text
C:\Users\admin\DevEcoStudioProjects\SemaLink\entry\build\default\outputs\default\entry-default-signed.hap
```

确认文件存在：

```powershell
Test-Path $hap
```

预期：

```text
True
```

可选：记录 HAP 的 SHA-256：

```powershell
Get-FileHash $hap -Algorithm SHA256
```

---

# 七、安装到设备 A

## 7.1 覆盖安装

```powershell
& $hdc -t $deviceA app install -r $hap
```

安装成功时通常会显示：

```text
success
```

或：

```text
install bundle successfully
```

## 7.2 验证设备 A 安装结果

```powershell
& $hdc -t $deviceA shell bm dump -n $bundle |
  Select-String -Pattern 'bundleName|versionName|versionCode|EntryAbility'
```

预期包含：

```text
bundleName: com.example.semalink
versionName: 1.0.0
versionCode: 1000000
EntryAbility
```

## 7.3 启动设备 A 上的应用

```powershell
& $hdc -t $deviceA shell aa start `
  -a EntryAbility `
  -b $bundle
```

## 7.4 强制停止设备 A 上的应用

```powershell
& $hdc -t $deviceA shell aa force-stop -b $bundle
```

## 7.5 设备 A 覆盖安装失败时

```powershell
& $hdc -t $deviceA app uninstall -n $bundle
& $hdc -t $deviceA app install $hap
& $hdc -t $deviceA shell aa start -a EntryAbility -b $bundle
```

注意：卸载会清除应用本地数据。

---

# 八、一键编译并安装到平板 B

```powershell
$node = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$hdc = 'D:\Program Files\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'

$deviceB = '5KLBB25B07200723'
$bundle = 'com.example.semalink'

& $node $hvigor --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  assembleHap

if ($LASTEXITCODE -ne 0) {
  throw 'HAP 编译失败，已停止安装'
}

$hap = Get-ChildItem .\entry\build -Recurse -Filter '*-signed.hap' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $hap -or -not (Test-Path $hap)) {
  throw '未找到已签名 HAP'
}

$targets = & $hdc list targets

if ($targets -notcontains $deviceB) {
  throw "未发现平板 B：$deviceB"
}

& $hdc -t $deviceB app install -r $hap

if ($LASTEXITCODE -ne 0) {
  throw '平板 B 安装失败'
}

& $hdc -t $deviceB shell aa start `
  -a EntryAbility `
  -b $bundle

if ($LASTEXITCODE -ne 0) {
  throw '平板 B 应用启动失败'
}

Write-Host 'SemaLink 已成功编译、安装并启动到平板 B。'
```

# 九、推荐日常开发执行顺序

每次修改代码后：

```text
1. 编译 signed HAP。
2. 确认 BUILD SUCCESSFUL。
3. 获取最新 HAP 路径。
4. 确认 A、B 都在线。
5. 同一个 HAP 覆盖安装到 A、B。
6. 验证两台设备版本一致。
7. 根据测试方向只启动发起端。
8. 观察响应端是否被系统自动拉起。
9. 测试查询、断开和手动重连。
10. 保存两端 hilog 日志。
```
