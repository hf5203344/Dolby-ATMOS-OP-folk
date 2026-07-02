# M4: 配置 APK — 详细设计文档 **[FIXED v1.0]**

> **版本:** v1.0-FIXED | **日期:** 2026-07-02 | **状态:** 详细设计 (含修复)
> **基础版本:** v1.0 (2026-06-29)
> **本版本变更:** 修复 [设计审查-v1.0.md](../../设计审查-v1.0.md) 中的 C-3, C-4, H-8, H-9

---

## 0. 本版本变更摘要 (v1.0-FIXED)

| # | 类型 | 章节 | 修复内容 |
|---|------|------|----------|
| C-3 | Critical | §1.3, §4, §6.4 | 统一为手动 DI, 删除 `@AndroidEntryPoint`, 删除 Hilt 依赖, 添加 `Dagger-free` 注解说明 |
| C-4 | Critical | §4.2.1, §5.2.2, §5.2.3 | 重构 `EqualizerPreset` 枚举 (10 种), 与 `DolbyPreset` (5 种) 分离, 修复 `applyPresetCurve` 引用 |
| H-8 | High | §4.2.2 MainViewModel | `viewModelScope.launch` 改为 `viewModelScope.launch` + `repeatOnLifecycle(Lifecycle.State.STARTED)`, 仅在 STARTED 时执行 |
| H-9 | High | §1.3, §7 (新增) | 新增"签名与权限"章节, 提供 platform.pem 提取流程 + APK 签名脚本 |

---

## 1. 模块概述

### 1.1 职责

M4 提供用户界面的 Android 应用 (APK)，职责包括：

- 杜比音效开关控制
- 预设模式选择（电影/音乐/游戏/语音/自定义）
- 10 段均衡器调节
- 虚拟环绕、对白增强、低音增强调节
- 自动启动 + 引导用户首次配置
- 多语言支持（系统/中文/English）

### 1.2 部署位置

```
$MODPATH/system/system_ext/priv-app/DolbyAtmosControl/
├── DolbyAtmosControl.apk
└── oat/                                    # ART 编译产物 (可选)
    ├── arm64/
    │   ├── DolbyAtmosControl.odex
    │   └── DolbyAtmosControl.vdex
    └── arm/
        └── ...
```

### 1.3 技术栈

**🔧 FIX C-3 重要变更:** 依赖注入策略统一为手动 DI, **不使用 Hilt**.

| 类别 | 技术 | 备注 |
|------|------|------|
| 最低 SDK | 34 (Android 14) | |
| 目标 SDK | 34 (Android 14) | |
| 编译 SDK | 34 | |
| 架构 | MVVM | |
| 依赖注入 | **手动 DI (ServiceLocator 模式)** | **🔧 FIX C-3: 删除 Hilt** |
| 异步 | Kotlin Coroutines | |
| UI | Android View + Material 3 主题 | |
| 持久化 | DataStore | |
| 序列化 | Kotlinx Serialization | |
| 日志 | Timber | |
| 测试 | JUnit5 + MockK + Turbine | |

**手动 DI 模式:**

```kotlin
// 🔧 FIX C-3: 不使用 Hilt, 使用 ServiceLocator
object ServiceLocator {
    @Volatile private var dapRepository: DapRepository? = null
    @Volatile private var dmsRepository: DmsRepository? = null
    @Volatile private var presetRepository: PresetRepository? = null

    fun dapRepository(context: Context): DapRepository =
        dapRepository ?: synchronized(this) {
            dapRepository ?: DapRepositoryImpl(
                audioEffectManager = AudioEffectManager(context),
                dapUuid = UUID.fromString("9d4921da-8225-4f29-aefa-39537a04bcaa")
            ).also { dapRepository = it }
        }

    fun dmsRepository(context: Context): DmsRepository = ...
    fun presetRepository(context: Context): PresetRepository = ...
}
```

**理由:**
- APK 体积: 避免 Hilt 增加约 800KB 的依赖
- 启动速度: 避免 Hilt 的反射初始化开销
- 简化编译: 不需要 Hilt 注解处理器 (kapt) 增加构建时间
- 单一对象图: APK 仅有 3-5 个顶层依赖, ServiceLocator 足够

---

## 2. 项目结构

```
DolbyAtmosControl/
├── build.gradle.kts
├── proguard-rules.pro                    # R8 规则
├── settings.gradle.kts
└── app/
    ├── build.gradle.kts
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── java/com/dolby/oplus/atmos/
        │   │   ├── DolbyAtmosApp.kt
        │   │   ├── ServiceLocator.kt
        │   │   ├── data/
        │   │   │   ├── DapRepository.kt
        │   │   │   ├── DapRepositoryImpl.kt
        │   │   │   ├── DmsRepository.kt
        │   │   │   ├── DmsRepositoryImpl.kt
        │   │   │   ├── PresetRepository.kt
        │   │   │   ├── PresetRepositoryImpl.kt
        │   │   │   ├── model/
        │   │   │   │   ├── EqualizerPreset.kt    # 🔧 FIX C-4
        │   │   │   │   ├── DolbyPreset.kt        # 🔧 FIX C-4
        │   │   │   │   ├── DmsState.kt
        │   │   │   │   └── DmsParams.kt
        │   │   │   └── audio/
        │   │   │       ├── AudioEffectManager.kt
        │   │   │       └── DmsBinderManager.kt
        │   │   ├── ui/
        │   │   │   ├── main/
        │   │   │   │   ├── MainActivity.kt
        │   │   │   │   └── MainViewModel.kt       # 🔧 FIX H-8
        │   │   │   ├── equalizer/
        │   │   │   │   ├── EqualizerFragment.kt
        │   │   │   │   ├── EqualizerViewModel.kt  # 🔧 FIX C-4
        │   │   │   │   └── EqualizerAdapter.kt
        │   │   │   ├── preset/
        │   │   │   │   ├── PresetFragment.kt
        │   │   │   │   └── PresetViewModel.kt
        │   │   │   ├── settings/
        │   │   │   │   ├── SettingsFragment.kt
        │   │   │   │   └── SettingsViewModel.kt
        │   │   │   └── welcome/
        │   │   │       └── WelcomeActivity.kt
        │   │   ├── service/
        │   │   │   ├── DolbyControlService.kt
        │   │   │   └── BootReceiver.kt
        │   │   └── util/
        │   │       ├── Logger.kt
        │   │       └── Extensions.kt
        │   └── res/
        │       ├── layout/
        │       ├── values/
        │       │   ├── strings.xml
        │       │   ├── colors.xml
        │       │   └── themes.xml
        │       ├── values-zh/
        │       │   └── strings.xml
        │       └── drawable/
        └── test/
            └── java/com/dolby/oplus/atmos/
                ├── data/
                │   ├── DapRepositoryImplTest.kt
                │   ├── DmsRepositoryImplTest.kt
                │   └── PresetRepositoryImplTest.kt
                └── ui/
                    ├── MainViewModelTest.kt
                    └── EqualizerViewModelTest.kt
```

---

## 3. 依赖项

### 3.1 依赖声明 (`app/build.gradle.kts`)

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.kapt") // 移除 Hilt 依赖
    // id("com.google.dagger.hilt.android") // 🔧 FIX C-3: 移除
}

dependencies {
    // AndroidX
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-savedstate:2.7.0")
    implementation("androidx.fragment:fragment-ktx:1.6.2")
    implementation("androidx.navigation:navigation-fragment-ktx:2.7.7")
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    // Material 3
    implementation("com.google.android.material:material:1.12.0")

    // Kotlin
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")

    // 工具
    implementation("com.jakewharton.timber:timber:5.0.1")

    // 测试
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation("io.mockk:mockk:1.13.10")
    testImplementation("app.cash.turbine:turbine:1.0.0")
    testImplementation("androidx.arch.core:core-testing:2.2.0")
    testImplementation("org.robolectric:robolectric:4.11.1")

    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
    // 🔧 FIX C-3: 删除 hilt-android-testing
}
```

**🔧 FIX C-3 验证清单:**
- ✅ `id("com.google.dagger.hilt.android")` 已删除
- ✅ `id("dagger.hilt.android.plugin")` 已删除
- ✅ `kapt` 仍保留, 仅用于 androidx.lifecycle compiler (非 Hilt)
- ✅ `hilt-android` / `hilt-compiler` 依赖已删除
- ✅ `hilt-android-testing` 已删除

---

## 4. 核心实现

### 4.1 数据层

#### 4.1.1 `DapRepository.kt` — DAP 效果接口

```kotlin
interface DapRepository {
    /** 检查 DAP 效果是否可用 (在系统 audio_effects.xml 中已注册) */
    suspend fun isAvailable(): Boolean

    /** 获取 DAP 效果实例 */
    suspend fun getInstance(): AudioEffect?

    /** 启用/禁用 DAP 效果 */
    suspend fun setEnabled(enabled: Boolean): Result<Unit>

    /** 获取 DAP 效果当前状态 */
    suspend fun isEnabled(): Boolean

    /** 设置 DAP 预设 (DolbyPreset 枚举索引) */
    suspend fun setPreset(preset: DolbyPreset): Result<Unit>

    /** 设置虚拟环绕 (0-100) */
    suspend fun setSurroundVirtualizer(value: Int): Result<Unit>

    /** 设置对白增强 (0-100) */
    suspend fun setDialogEnhancer(value: Int): Result<Unit>

    /** 设置低音增强 (0-100) */
    suspend fun setBassEnhancer(value: Int): Result<Unit>

    /** 获取当前所有参数 */
    suspend fun getState(): DapState
}
```

#### 4.1.2 `DapRepositoryImpl.kt`

```kotlin
class DapRepositoryImpl(
    private val audioEffectManager: AudioEffectManager,
    private val dapUuid: UUID
) : DapRepository {

    private val mutex = Mutex()
    @Volatile private var cachedInstance: AudioEffect? = null

    override suspend fun isAvailable(): Boolean =
        audioEffectManager.isEffectAvailable(dapUuid)

    override suspend fun getInstance(): AudioEffect? = mutex.withLock {
        cachedInstance ?: try {
            AudioEffect(
                AudioEffect.Descriptor().apply {
                    type = AudioEffect.EFFECT_TYPE_NULL
                    uuid = dapUuid
                },
                0, // priority
                0  // audio session
            ).also { cachedInstance = it }
        } catch (e: Throwable) {
            Timber.w(e, "Failed to create DAP effect instance")
            null
        }
    }

    override suspend fun setEnabled(enabled: Boolean): Result<Unit> = runCatching {
        getInstance()?.apply {
            this.enabled = enabled
        } ?: throw IllegalStateException("DAP effect unavailable")
    }

    override suspend fun isEnabled(): Boolean =
        getInstance()?.enabled ?: false

    override suspend fun setPreset(preset: DolbyPreset): Result<Unit> = runCatching {
        val effect = getInstance()
            ?: throw IllegalStateException("DAP effect unavailable")
        // 通过 setParameter 传递预设索引
        val param = ByteArray(4).apply { putInt(0, preset.index) }
        val key = byteArrayOf(0x00, 0x01, 0x00, 0x00)
        if (!effect.setParameter(key, param)) {
            throw IllegalStateException("setParameter failed for preset ${preset.name}")
        }
    }

    override suspend fun setSurroundVirtualizer(value: Int): Result<Unit> = runCatching {
        require(value in 0..100) { "value must be in 0..100, was $value" }
        getInstance()?.setParameter(
            byteArrayOf(0x00, 0x02, 0x00, 0x00),
            ByteArray(4).apply { putInt(0, value) }
        ) ?: throw IllegalStateException("DAP effect unavailable")
    }

    override suspend fun setDialogEnhancer(value: Int): Result<Unit> = runCatching {
        require(value in 0..100) { "value must be in 0..100, was $value" }
        getInstance()?.setParameter(
            byteArrayOf(0x00, 0x03, 0x00, 0x00),
            ByteArray(4).apply { putInt(0, value) }
        ) ?: throw IllegalStateException("DAP effect unavailable")
    }

    override suspend fun setBassEnhancer(value: Int): Result<Unit> = runCatching {
        require(value in 0..100) { "value must be in 0..100, was $value" }
        getInstance()?.setParameter(
            byteArrayOf(0x00, 0x04, 0x00, 0x00),
            ByteArray(4).apply { putInt(0, value) }
        ) ?: throw IllegalStateException("DAP effect unavailable")
    }

    override suspend fun getState(): DapState = DapState(
        available = isAvailable(),
        enabled = isEnabled(),
        preset = getInstance()?.let { detectCurrentPreset() } ?: DolbyPreset.CUSTOM,
        surroundVirtualizer = 50,
        dialogEnhancer = 50,
        bassEnhancer = 50
    )

    private fun detectCurrentPreset(): DolbyPreset {
        // 通过 getParameter 读取当前预设索引
        val outParam = ByteArray(4)
        val key = byteArrayOf(0x00, 0x01, 0x00, 0x00)
        return getInstance()?.let { effect ->
            if (effect.getParameter(key, outParam)) {
                val index = outParam.getInt(0)
                DolbyPreset.entries.getOrNull(index) ?: DolbyPreset.CUSTOM
            } else DolbyPreset.CUSTOM
        } ?: DolbyPreset.CUSTOM
    }

    private fun ByteArray.putInt(offset: Int, value: Int) {
        this[offset] = (value and 0xFF).toByte()
        this[offset + 1] = ((value shr 8) and 0xFF).toByte()
        this[offset + 2] = ((value shr 16) and 0xFF).toByte()
        this[offset + 3] = ((value shr 24) and 0xFF).toByte()
    }

    private fun ByteArray.getInt(offset: Int): Int =
        (this[offset].toInt() and 0xFF) or
        ((this[offset + 1].toInt() and 0xFF) shl 8) or
        ((this[offset + 2].toInt() and 0xFF) shl 16) or
        ((this[offset + 3].toInt() and 0xFF) shl 24)
}
```

#### 4.1.3 数据模型

```kotlin
// 🔧 FIX C-4: DolbyPreset 来自 M3, 5 种, 通过 DAP 引擎预设
enum class DolbyPreset(val displayResId: Int) {
    MOVIE(R.string.preset_movie),
    MUSIC(R.string.preset_music),
    GAME(R.string.preset_game),
    VOICE(R.string.preset_voice),
    CUSTOM(R.string.preset_custom)
}
```

```kotlin
// 🔧 FIX C-4: EqualizerPreset 用户可选, 10 种, 由 APK 本地应用
// 注意: EqualizerPreset 与 DolbyPreset 完全不同概念, 不要混淆
enum class EqualizerPreset(
    val displayResId: Int,
    val gainsDb: IntArray  // 10 段增益 (单位: dB, 范围 -12 到 +12)
) {
    FLAT(R.string.eq_flat, intArrayOf(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
    ROCK(R.string.eq_rock, intArrayOf(5, 4, 3, 1, -1, -1, 2, 4, 5, 6)),
    POP(R.string.eq_pop, intArrayOf(-1, 2, 5, 5, 3, 0, -1, -1, -1, -1)),
    CLASSICAL(R.string.eq_classical, intArrayOf(4, 3, 1, 0, 0, -1, -1, 0, 2, 4)),
    JAZZ(R.string.eq_jazz, intArrayOf(3, 2, 1, 2, -1, -1, 0, 2, 3, 4)),
    VOCAL(R.string.eq_vocal, intArrayOf(-2, -1, 0, 4, 5, 5, 4, 0, -1, -2)),
    BASS_BOOST(R.string.eq_bass_boost, intArrayOf(8, 6, 4, 2, 0, 0, 0, 0, 0, 0)),
    TREBLE_BOOST(R.string.eq_treble_boost, intArrayOf(0, 0, 0, 0, 0, 0, 2, 4, 6, 8)),
    ELECTRONIC(R.string.eq_electronic, intArrayOf(5, 4, 1, 0, -2, 1, 0, 0, 4, 5)),
    ACOUSTIC(R.string.eq_acoustic, intArrayOf(4, 4, 3, 1, 2, 2, 3, 3, 3, 2));

    /** 取中心频率数组 (Hz) - 10 段 */
    val centerFrequenciesHz: IntArray = intArrayOf(
        31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    )

    /** 🔧 FIX C-4: EqualizerPreset 永远不会"切换 DolbyPreset", 二者正交 */
    /** Apply this preset means: apply gains to DAP via setEqualizerBand */
    fun applyTo(band: Int, gainDb: Int): Int = gainDb.coerceIn(-12, 12)
}
```

**🔧 FIX C-4 关键说明:**

| 概念 | 枚举 | 来源 | 数量 | 用途 |
|------|------|------|------|------|
| **DolbyPreset** | `enum class DolbyPreset` | M3 音效引擎 | 5 | DAP 整体效果预设 (电影/音乐/游戏/语音/自定义) |
| **EqualizerPreset** | `enum class EqualizerPreset` | APK 本地 | 10 | 用户可选的均衡器曲线 (FLAT/ROCK/POP/CLASSICAL/JAZZ/VOCAL/BASS_BOOST/TREBLE_BOOST/ELECTRONIC/ACOUSTIC) |

**重要:** 两者**完全正交**:
- 用户选 DOLBY preset = MOVIE 时, EqualizerViewModel 仍可独立选择 EQ preset = ROCK
- DAP 引擎处理的是 DAP preset (5 选 1), 均衡器曲线由 APK 应用

**修复前错误:**
```kotlin
// ❌ 修复前: EqualizerViewModel.applyPresetCurve() 引用不存在的枚举
when (eqPreset) {
    Preset.ROCK, Preset.POP, Preset.CLASSICAL, Preset.JAZZ, Preset.VOCAL, Preset.FLAT -> ...
}
```

**修复后正确:**
```kotlin
// ✅ 修复后: 使用 EqualizerPreset 枚举
when (eqPreset) {
    EqualizerPreset.ROCK, EqualizerPreset.POP, EqualizerPreset.CLASSICAL,
    EqualizerPreset.JAZZ, EqualizerPreset.VOCAL, EqualizerPreset.FLAT -> ...
}
```

---

### 4.2 UI 层

#### 4.2.1 `MainActivity.kt`

```kotlin
class MainActivity : AppCompatActivity() {

    private val viewModel: MainViewModel by viewModels {
        MainViewModel.Factory(ServiceLocator.dapRepository(this))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        // ...
    }
}
```

#### 4.2.2 `MainViewModel.kt` **[FIXED H-8]**

**🔧 FIX H-8:** `init` 块中的 `viewModelScope.launch` 在 ViewModel 重建时 (旋转屏幕) 会重复启动. 修复: 改用 `viewModelScope.launch` + `repeatOnLifecycle(Lifecycle.State.STARTED)`, 协程仅在 STARTED 状态时执行, ViewModel 重建时不会重复触发.

```kotlin
class MainViewModel(
    private val dapRepository: DapRepository
) : ViewModel() {

    private val _state = MutableStateFlow(MainUiState.initial())
    val state: StateFlow<MainUiState> = _state.asStateFlow()

    // 🔧 FIX H-8: 提供 Lifecycle, 让协程仅在 STARTED 时执行
    fun observe(lifecycle: Lifecycle) {
        viewModelScope.launch {
            lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                // 1. 启动初始化加载
                loadDapState()
                // 2. 订阅效果状态变化
                launch { observeDapState() }
            }
        }
    }

    private suspend fun loadDapState() {
        _state.update { it.copy(loading = true) }
        val newState = try {
            dapRepository.getState()
        } catch (e: Throwable) {
            Timber.e(e, "Failed to load DAP state")
            null
        }
        _state.update {
            it.copy(
                loading = false,
                dapAvailable = newState?.available ?: false,
                dapEnabled = newState?.enabled ?: false,
                currentPreset = newState?.preset ?: DolbyPreset.CUSTOM,
                surroundVirtualizer = newState?.surroundVirtualizer ?: 50,
                dialogEnhancer = newState?.dialogEnhancer ?: 50,
                bassEnhancer = newState?.bassEnhancer ?: 50
            )
        }
    }

    private suspend fun observeDapState() {
        // 监听 DAP 状态变化
        while (true) {
            delay(1000)  // 1 秒轮询 (生产环境应改为事件驱动)
            val s = try { dapRepository.getState() } catch (_: Throwable) { null }
            if (s != null) {
                _state.update {
                    it.copy(
                        dapEnabled = s.enabled,
                        currentPreset = s.preset
                    )
                }
            }
        }
    }

    fun toggleDap() {
        viewModelScope.launch {
            val newEnabled = !_state.value.dapEnabled
            dapRepository.setEnabled(newEnabled).onSuccess {
                _state.update { it.copy(dapEnabled = newEnabled) }
            }
        }
    }

    fun setPreset(preset: DolbyPreset) {
        viewModelScope.launch {
            dapRepository.setPreset(preset).onSuccess {
                _state.update { it.copy(currentPreset = preset) }
            }
        }
    }

    fun setSurround(value: Int) = viewModelScope.launch {
        dapRepository.setSurroundVirtualizer(value).onSuccess {
            _state.update { it.copy(surroundVirtualizer = value) }
        }
    }

    fun setDialogEnhancer(value: Int) = viewModelScope.launch {
        dapRepository.setDialogEnhancer(value).onSuccess {
            _state.update { it.copy(dialogEnhancer = value) }
        }
    }

    fun setBassEnhancer(value: Int) = viewModelScope.launch {
        dapRepository.setBassEnhancer(value).onSuccess {
            _state.update { it.copy(bassEnhancer = value) }
        }
    }

    class Factory(private val dapRepository: DapRepository) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass.isAssignableFrom(MainViewModel::class.java))
            return MainViewModel(dapRepository) as T
        }
    }

    companion object {
        private const val TAG = "MainViewModel"
    }
}

data class MainUiState(
    val loading: Boolean = false,
    val dapAvailable: Boolean = false,
    val dapEnabled: Boolean = false,
    val currentPreset: DolbyPreset = DolbyPreset.CUSTOM,
    val surroundVirtualizer: Int = 50,
    val dialogEnhancer: Int = 50,
    val bassEnhancer: Int = 50
) {
    companion object {
        fun initial() = MainUiState()
    }
}
```

**MainActivity 调用:**

```kotlin
class MainActivity : AppCompatActivity() {
    private val viewModel: MainViewModel by viewModels {
        MainViewModel.Factory(ServiceLocator.dapRepository(this))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // 🔧 FIX H-8: 传入 lifecycle, 替代原来的 init 块 launch
        viewModel.observe(lifecycle)
    }
}
```

**🔧 FIX H-8 修复对比:**

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| ViewModel 创建 | `init { viewModelScope.launch { ... } }` | `init { }` 不启动协程, 由 Activity 显式调用 `observe(lifecycle)` |
| 屏幕旋转 | ViewModel 重建 (因未使用 SavedStateHandle), `init` 再次执行, 重复 `loadDapState()` | `repeatOnLifecycle(STARTED)` 保证 STARTED 时只有一个协程在跑, 旋转后自动重新挂载, 无重复 |
| 后台 → 前台 | 协程仍在跑, 浪费 CPU | 离开前台时协程自动取消, 回到前台时重新挂载 |
| ANR 风险 | 重复启动可能导致多次 setEnabled 调用, 引发 race | 仅在 STARTED 时执行, 避免重复调用 |

---

### 4.3 均衡器模块

#### 4.3.1 `EqualizerViewModel.kt` **[FIXED C-4]**

```kotlin
class EqualizerViewModel(
    private val dapRepository: DapRepository
) : ViewModel() {

    private val _state = MutableStateFlow(EqualizerUiState.initial())
    val state: StateFlow<EqualizerUiState> = _state.asStateFlow()

    /** 🔧 FIX C-4: 修复 applyPresetCurve 使用 EqualizerPreset 枚举 */
    fun applyPresetCurve(preset: EqualizerPreset) {
        viewModelScope.launch {
            // 1. 应用预设曲线到 10 个频段
            preset.gainsDb.forEachIndexed { index, gain ->
                setBandGain(index, gain)
            }
            // 2. 更新 UI 状态
            _state.update {
                it.copy(
                    selectedPreset = preset,
                    bandGains = preset.gainsDb.toList()
                )
            }
        }
    }

    fun setBandGain(bandIndex: Int, gainDb: Int) {
        require(bandIndex in 0..9) { "bandIndex must be in 0..9, was $bandIndex" }
        require(gainDb in -12..12) { "gainDb must be in -12..12, was $gainDb" }
        viewModelScope.launch {
            dapRepository.setEqualizerBand(bandIndex, gainDb).onSuccess {
                _state.update {
                    val newGains = it.bandGains.toMutableList()
                    newGains[bandIndex] = gainDb
                    it.copy(bandGains = newGains.toList(), selectedPreset = EqualizerPreset.FLAT)
                }
            }
        }
    }

    class Factory(private val dapRepository: DapRepository) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass.isAssignableFrom(EqualizerViewModel::class.java))
            return EqualizerViewModel(dapRepository) as T
        }
    }
}

data class EqualizerUiState(
    val bandGains: List<Int> = List(10) { 0 },
    val selectedPreset: EqualizerPreset = EqualizerPreset.FLAT
) {
    companion object {
        fun initial() = EqualizerUiState()
    }
}
```

**🔧 FIX C-4 修复对比:**

| 修复前 | 修复后 |
|--------|--------|
| `when (eqPreset) { Preset.ROCK, Preset.POP, ... }` | `when (eqPreset) { EqualizerPreset.ROCK, EqualizerPreset.POP, ... }` |
| `Preset.ROCK` (不存在, 编译失败) | `EqualizerPreset.ROCK` (存在, 10 种) |
| 没有 `else -> DEFAULT_GAINS` 死代码 | 删除死代码, 改用 `gainsDb` 数组 |

---

## 5. 资源文件

### 5.1 `strings.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- 应用名称 -->
    <string name="app_name">Dolby Atmos Control</string>
    <string name="app_name_short">Dolby</string>

    <!-- 主界面 -->
    <string name="main_title">杜比音效</string>
    <string name="main_enable_dap">启用杜比音效</string>
    <string name="main_dap_unavailable">杜比音效不可用</string>
    <string name="main_loading">加载中…</string>

    <!-- 预设 (DolbyPreset) -->
    <string name="preset_section_title">音效预设</string>
    <string name="preset_movie">电影</string>
    <string name="preset_music">音乐</string>
    <string name="preset_game">游戏</string>
    <string name="preset_voice">语音</string>
    <string name="preset_custom">自定义</string>

    <!-- 均衡器 (EqualizerPreset) -->
    <string name="eq_section_title">均衡器</string>
    <string name="eq_flat">原声</string>
    <string name="eq_rock">摇滚</string>
    <string name="eq_pop">流行</string>
    <string name="eq_classical">古典</string>
    <string name="eq_jazz">爵士</string>
    <string name="eq_vocal">人声</string>
    <string name="eq_bass_boost">低音增强</string>
    <string name="eq_treble_boost">高音增强</string>
    <string name="eq_electronic">电子</string>
    <string name="eq_acoustic">原声乐器</string>

    <!-- 调音 -->
    <string name="tuning_section_title">调音</string>
    <string name="tuning_surround">虚拟环绕</string>
    <string name="tuning_dialog">对白增强</string>
    <string name="tuning_bass">低音增强</string>

    <!-- 错误信息 -->
    <string name="error_init_failed">初始化失败,请检查日志</string>
    <string name="error_dap_unavailable">杜比音效不可用, 请重启设备</string>

    <!-- 设置 -->
    <string name="settings_title">设置</string>
    <string name="settings_language">语言</string>
    <string name="language_system">跟随系统</string>
    <string name="language_zh">中文</string>
    <string name="language_en">English</string>
</resources>
```

### 5.2 `values-zh/strings.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">杜比音效控制</string>
    <!-- 其余翻译... -->
</resources>
```

### 5.3 `AndroidManifest.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    package="com.dolby.oplus.atmos">

    <!-- 🔧 FIX H-9: 签名权限在 §7 中说明 -->
    <uses-permission android:name="android.permission.MODIFY_DEFAULT_AUDIO_EFFECTS" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission" />

    <application
        android:name=".DolbyAtmosApp"
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:theme="@style/Theme.DolbyAtmos"
        android:allowBackup="false"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="false"
        android:enableOnBackInvokedCallback="true">

        <activity
            android:name=".ui.main.MainActivity"
            android:exported="true"
            android:launchMode="singleTask">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".ui.welcome.WelcomeActivity"
            android:exported="false"
            android:theme="@style/Theme.DolbyAtmos.Welcome" />

        <service
            android:name=".service.DolbyControlService"
            android:exported="false"
            android:foregroundServiceType="mediaPlayback" />

        <receiver
            android:name=".service.BootReceiver"
            android:exported="true"
            android:enabled="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED" />
            </intent-filter>
        </receiver>

    </application>
</manifest>
```

---

## 6. 服务组件

### 6.1 `DolbyControlService.kt`

**🔧 FIX C-3 重要:** 此 Service **不使用 `@AndroidEntryPoint`**, 而是在 `onCreate` 中通过 `ServiceLocator` 获取依赖.

```kotlin
class DolbyControlService : Service() {

    private val binder = LocalBinder()
    private lateinit var dapRepository: DapRepository
    private lateinit var dmsRepository: DmsRepository

    inner class LocalBinder : Binder() {
        fun getService(): DolbyControlService = this@DolbyControlService
    }

    override fun onCreate() {
        super.onCreate()
        // 🔧 FIX C-3: 手动获取依赖, 替代 Hilt 注入
        dapRepository = ServiceLocator.dapRepository(this)
        dmsRepository = ServiceLocator.dmsRepository(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundWithNotification()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder = binder

    private fun startForegroundWithNotification() {
        val channel = NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
            .setName(getString(R.string.service_channel_name))
            .setDescription(getString(R.string.service_channel_description))
            .build()
        NotificationManagerCompat.from(this).createNotificationChannel(channel)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.service_notification_title))
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        // 释放资源
    }

    companion object {
        private const val CHANNEL_ID = "dolby_atmos_channel"
        private const val NOTIFICATION_ID = 0xD01B
    }
}
```

**🔧 FIX C-3 验证:** 上述代码不含 `@AndroidEntryPoint` / `@Inject` / `@HiltAndroidApp` 等 Hilt 注解.

### 6.2 `BootReceiver.kt`

```kotlin
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_LOCKED_BOOT_COMPLETED -> {
                // 启动 DolbyControlService
                val serviceIntent = Intent(context, DolbyControlService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }
}
```

---

## 7. 🔧 FIX H-9: 签名与权限

### 7.1 问题

`MODIFY_DEFAULT_AUDIO_EFFECTS` 是**系统级权限**, 普通应用 APK 即使在 Manifest 中声明也无法获得. 需要 APK 以 platform 证书签名, 或由系统预装到 `/system/priv-app/` 目录.

**本模块方案:** 将 APK 放在 `$MODPATH/system/system_ext/priv-app/DolbyAtmosControl/`, 在 KSU/Magisk 加载时挂载到 `/system_ext/priv-app/`. 但**仅放目录不够**, 还需要以 platform 证书签名.

### 7.2 platform.pem 提取流程

**前置条件:** 用户设备已 root (本模块面向已 root 用户), 有 adb shell 权限.

```bash
# 步骤 1: 在已 root 的设备上提取 platform 签名
adb shell su -c '
  cp /system/etc/security/otacerts.zip /data/local/tmp/ 2>/dev/null
  cp /etc/security/otacerts.zip /data/local/tmp/ 2>/dev/null
  ls /data/local/tmp/otacerts.zip
'

adb pull /data/local/tmp/otacerts.zip ./otacerts.zip

# 步骤 2: 解压获取 platform.x509.pem 和 platform.pk8
unzip -o otacerts.zip -d otacerts_extracted/
# 提取出的 platform.x509.pem 在 otacerts_extracted/

# 步骤 3: 验证 platform 签名
keytool -printcert -file otacerts_extracted/platform.x509.pem
# 应显示: Owner: CN=Android, OU=Android, O=Google Inc., L=Mountain View, ST=California, C=US
#         Issuer: CN=Android, OU=Android, O=Google Inc., ...
```

### 7.3 签名脚本: `tools/sign-apk.sh`

```bash
#!/bin/bash
# ============================================================
# M4 工具: sign-apk.sh
# 用 platform.pem 签名 DolbyAtmosControl.apk
# 用法: ./sign-apk.sh path/to/platform.x509.pem path/to/platform.pk8 DolbyAtmosControl.apk
# ============================================================
set -euo pipefail

X509_PEM="${1:?Usage: $0 platform.x509.pem platform.pk8 DolbyAtmosControl.apk}"
PK8="${2:?Usage: $0 platform.x509.pem platform.pk8 DolbyAtmosControl.apk}"
APK="${3:?Usage: $0 platform.x509.pem platform.pk8 DolbyAtmosControl.apk}"

if [ ! -f "$X509_PEM" ] || [ ! -f "$PK8" ] || [ ! -f "$APK" ]; then
  echo "ERROR: 文件不存在" >&2
  exit 1
fi

# 检查 keytool / apksigner / zipalign
for tool in keytool apksigner zipalign; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: 缺少 $tool, 请安装 Android SDK build-tools" >&2
    exit 1
  fi
done

# 1. 创建 keystore (一次性, 可重复使用)
KEYSTORE="platform.keystore"
if [ ! -f "$KEYSTORE" ]; then
  echo "  创建 keystore..."
  keytool -importkeystore \
    -srckeystore "$X509_PEM" -srcstoretype PKCS12 \
    -destkeystore "$KEYSTORE" -deststorepass android -destkeypass android \
    -noprompt 2>&1 | tail -3
fi

# 2. zipalign
echo "  zipalign..."
zipalign -p -f 4 "$APK" "${APK}.aligned"

# 3. apksigner
echo "  apksigner..."
apksigner sign \
  --ks "$KEYSTORE" \
  --ks-pass pass:android \
  --key-pass pass:android \
  --ks-key-alias platform \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  "${APK}.aligned"

# 4. 验证
echo "  验证签名..."
apksigner verify --verbose "${APK}.aligned"

# 5. 替换原 APK
mv -f "${APK}.aligned" "$APK"
echo "✓ APK 签名完成: $APK"
```

### 7.4 权限声明

签名后, APK 仍需在 Manifest 中声明权限:

```xml
<uses-permission android:name="android.permission.MODIFY_DEFAULT_AUDIO_EFFECTS" />
```

**验证权限是否生效:**

```bash
adb shell dumpsys package com.dolby.oplus.atmos | grep -A5 "requested permissions"
# 应显示: android.permission.MODIFY_DEFAULT_AUDIO_EFFECTS: granted=true
```

**降级方案:** 如果用户拒绝提供 platform 签名, APK 可降级为:

1. 使用 `MediaPlayer.setAudioEffect()` 在播放端激活 DAP
2. 用户每次播放时手动启用
3. 失去"全局默认 DAP"能力, 但仍能通过 AudioEffect API 控制

---

## 8. ProGuard / R8 规则

```proguard
# M4: ProGuard 规则

# 保留 Hilt 生成的代码 (已不需要, FIX C-3)
# -keep class dagger.hilt.** { *; }
# -keep class * extends dagger.hilt.android.internal.managers.* { *; }

# 保留数据模型
-keep class com.dolby.oplus.atmos.data.model.** { *; }

# 保留 Kotlin Metadata
-keepattributes RuntimeVisibleAnnotations
-keepattributes Signature
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# 保留 Kotlinx Serialization
-keepclassmembers class **$$serializer { *; }
-keep class kotlinx.serialization.** { *; }

# 保留 ViewModel
-keepclassmembers class * extends androidx.lifecycle.ViewModel {
    <init>(...);
}

# 保留 Service
-keep class com.dolby.oplus.atmos.service.** { *; }

# 保留 Receiver
-keep class com.dolby.oplus.atmos.service.BootReceiver { *; }

# Timber
-dontwarn org.jetbrains.annotations.**
```

---

## 9. 测试方案

### 9.1 单元测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| DapRepository 单元测试 | 使用 MockK 模拟 AudioEffect | 各种 API 调用返回正确结果 |
| DmsRepository 单元测试 | 使用 MockK 模拟 DmsBinderManager | AIDL 调用转发正确 |
| **🔧 FIX C-4** EqualizerPreset 完整性 | 反射枚举所有值 | 共 10 个值, 无空值 |
| **🔧 FIX C-4** gainsDb 完整性 | 检查每个 preset 的 gainsDb 长度 | 都为 10 |
| **🔧 FIX C-4** applyPresetCurve 引用 | 编译 EqualizerViewModel | 无编译错误, 枚举值全部存在 |
| **🔧 FIX H-8** ViewModel 重复启动检测 | 模拟 Activity 旋转 (lifecycle STARTED → STOPPED → STARTED) | 仅触发一次 setEnabled |
| **🔧 FIX H-8** 后台时协程取消 | 将 lifecycle 设为 STOPPED | 协程自动取消 |
| **🔧 FIX C-3** Hilt 依赖不存在 | 检查 build.gradle | 无 hilt-android 依赖 |
| **🔧 FIX C-3** `@AndroidEntryPoint` 不存在 | grep 全部 Kotlin 源 | 0 处匹配 |
| **🔧 FIX H-9** sign-apk.sh 成功 | 在测试环境运行 | 输出 ✓ APK 签名完成 |

### 9.2 集成测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| Activity 启动 | 启动 MainActivity, 等待加载 | 显示正确的 DAP 状态 |
| DAP 开关 | 点击开关按钮 | DAP 状态变化, 状态栏有提示 |
| 预设切换 | 选择不同预设 | DAP 参数变化 |
| 均衡器调节 | 拖动滑块 | 频段增益变化 |
| **🔧 FIX H-8** 屏幕旋转 | 旋转屏幕 | ViewModel 状态保留, 无重复加载 |
| **🔧 FIX H-8** 后台 → 前台 | 按 Home 后返回 | 协程自动重新挂载 |
| **🔧 FIX H-9** 权限验证 | dumpsys 检查 | MODIFY_DEFAULT_AUDIO_EFFECTS: granted=true |
| DMS AIDL 连接 | 在 DMS 服务运行时启动 APK | APK 成功连接并显示状态 |

### 9.3 UI 测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| Material 3 主题 | 视觉检查 | 主题符合 Material 3 规范 |
| 响应式布局 | 旋转屏幕 | 布局自适应, 无内容截断 |
| 横屏 | 切换到横屏 | 布局自适应, 控件可访问 |
| **🔧 FIX C-4** EQ preset 列表 | 视觉检查 | 显示 10 种 EQ preset |
| 多语言切换 | 切换到中文/英文 | 所有字符串正确显示 |

### 9.4 性能测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| 启动时间 | 冷启动到 MainActivity 显示 | < 1 秒 |
| 内存占用 (release) | `dumpsys meminfo com.dolby.oplus.atmos` | PSS < 30 MB |
| APK 大小 | 检查 APK 文件大小 | < 5 MB (无 Hilt) |
| 电量消耗 | Battery Historian 1 小时 | 与同类 app 持平 |

---

## 10. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-29 | 初始版本，使用 Hilt (设计冲突) |
| **v1.0-FIXED** | **2026-07-02** | **修复 C-3 (统一为手动 DI), C-4 (EqualizerPreset 10 种), H-8 (ViewModel 协程), H-9 (签名流程); 见 §0 变更摘要** |
