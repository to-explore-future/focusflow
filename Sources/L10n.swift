import Foundation

/// 多语言。菜单里就十来个字符串，直接内嵌，不折腾 .lproj。
enum L10n {
    struct Lang {
        let code: String
        let name: String   // 语言自身的写法
        let strings: [String: String]
    }

    static let languages: [Lang] = [
        Lang(code: "zh-Hans", name: "简体中文", strings: [
            "enabled": "启用",
            "accessibility": "辅助功能权限",
            "granted": "已授权",
            "notGranted": "未授权（点击去授权）",
            "launchAtLogin": "开机自启动",
            "language": "语言",
            "version": "版本",
            "quit": "退出",
            "donate": "赞助",
            "donateLine1": "软件免费，赞助随意",
            "donateLine2": "能帮到你，就是最大的动力",
            "donateScan": "微信扫码",
            "tooltip": "FocusFlow — 鼠标跨屏时激活该屏上次的窗口",
        ]),
        Lang(code: "zh-Hant", name: "繁體中文", strings: [
            "enabled": "啟用",
            "accessibility": "輔助功能權限",
            "granted": "已授權",
            "notGranted": "未授權（點擊去授權）",
            "launchAtLogin": "開機自動啟動",
            "language": "語言",
            "version": "版本",
            "quit": "結束",
            "donate": "贊助",
            "donateLine1": "軟體免費，贊助隨意",
            "donateLine2": "能幫到你，就是最大的動力",
            "donateScan": "微信掃碼",
            "tooltip": "FocusFlow — 滑鼠跨螢幕時啟用該螢幕上次的視窗",
        ]),
        Lang(code: "en", name: "English", strings: [
            "enabled": "Enabled",
            "accessibility": "Accessibility Permission",
            "granted": "Granted",
            "notGranted": "Not granted (click to grant)",
            "launchAtLogin": "Launch at Login",
            "language": "Language",
            "version": "Version",
            "quit": "Quit",
            "donate": "Donate",
            "donateLine1": "Free software, tips optional",
            "donateLine2": "If it helps you, that's all the reward I need.",
            "donateScan": "Scan with WeChat",
            "tooltip": "FocusFlow — focus the last window on the display your cursor enters",
        ]),
        Lang(code: "ja", name: "日本語", strings: [
            "enabled": "有効",
            "accessibility": "アクセシビリティ権限",
            "granted": "許可済み",
            "notGranted": "未許可（クリックして許可）",
            "launchAtLogin": "ログイン時に起動",
            "language": "言語",
            "version": "バージョン",
            "quit": "終了",
            "donate": "応援",
            "donateLine1": "ソフトは無料、支援は任意",
            "donateLine2": "お役に立てることが一番の報酬です",
            "donateScan": "WeChatでスキャン",
            "tooltip": "FocusFlow — カーソルが移動したディスプレイの前回のウインドウを前面に",
        ]),
        Lang(code: "ko", name: "한국어", strings: [
            "enabled": "사용",
            "accessibility": "손쉬운 사용 권한",
            "granted": "허용됨",
            "notGranted": "허용 안 됨 (클릭하여 허용)",
            "launchAtLogin": "로그인 시 실행",
            "language": "언어",
            "version": "버전",
            "quit": "종료",
            "donate": "후원",
            "donateLine1": "무료 소프트웨어, 후원은 자유",
            "donateLine2": "도움이 되었다면 그것으로 충분합니다",
            "donateScan": "WeChat으로 스캔",
            "tooltip": "FocusFlow — 커서가 이동한 디스플레이의 마지막 윈도우를 활성화",
        ]),
        Lang(code: "de", name: "Deutsch", strings: [
            "enabled": "Aktiviert",
            "accessibility": "Bedienungshilfen-Zugriff",
            "granted": "Erteilt",
            "notGranted": "Nicht erteilt (zum Erteilen klicken)",
            "launchAtLogin": "Bei Anmeldung starten",
            "language": "Sprache",
            "version": "Version",
            "quit": "Beenden",
            "donate": "Unterstützen",
            "donateLine1": "Kostenlos, Spende optional",
            "donateLine2": "Wenn es dir hilft, ist das der beste Lohn.",
            "donateScan": "Mit WeChat scannen",
            "tooltip": "FocusFlow — aktiviert das letzte Fenster auf dem Bildschirm unter dem Cursor",
        ]),
        Lang(code: "fr", name: "Français", strings: [
            "enabled": "Activé",
            "accessibility": "Autorisation d’accessibilité",
            "granted": "Accordée",
            "notGranted": "Non accordée (cliquer pour accorder)",
            "launchAtLogin": "Ouvrir à la connexion",
            "language": "Langue",
            "version": "Version",
            "quit": "Quitter",
            "donate": "Soutenir",
            "donateLine1": "Logiciel gratuit, don facultatif",
            "donateLine2": "Si cela vous aide, c'est ma plus grande récompense.",
            "donateScan": "Scanner avec WeChat",
            "tooltip": "FocusFlow — active la dernière fenêtre de l’écran où arrive le curseur",
        ]),
        Lang(code: "es", name: "Español", strings: [
            "enabled": "Activado",
            "accessibility": "Permiso de accesibilidad",
            "granted": "Concedido",
            "notGranted": "No concedido (clic para conceder)",
            "launchAtLogin": "Abrir al iniciar sesión",
            "language": "Idioma",
            "version": "Versión",
            "quit": "Salir",
            "donate": "Apoyar",
            "donateLine1": "Software gratis, donativo opcional",
            "donateLine2": "Si te ayuda, esa es mi mayor recompensa.",
            "donateScan": "Escanear con WeChat",
            "tooltip": "FocusFlow — activa la última ventana de la pantalla a la que llega el cursor",
        ]),
        Lang(code: "it", name: "Italiano", strings: [
            "enabled": "Attivo",
            "accessibility": "Permesso Accessibilità",
            "granted": "Concesso",
            "notGranted": "Non concesso (clic per concedere)",
            "launchAtLogin": "Apri al login",
            "language": "Lingua",
            "version": "Versione",
            "quit": "Esci",
            "donate": "Sostieni",
            "donateLine1": "Software gratuito, offerta facoltativa",
            "donateLine2": "Se ti è utile, è la mia migliore ricompensa.",
            "donateScan": "Scansiona con WeChat",
            "tooltip": "FocusFlow — attiva l’ultima finestra dello schermo sotto il cursore",
        ]),
        Lang(code: "pt", name: "Português", strings: [
            "enabled": "Ativado",
            "accessibility": "Permissão de Acessibilidade",
            "granted": "Concedida",
            "notGranted": "Não concedida (clique para conceder)",
            "launchAtLogin": "Abrir ao iniciar sessão",
            "language": "Idioma",
            "version": "Versão",
            "quit": "Sair",
            "donate": "Apoiar",
            "donateLine1": "Software gratuito, doação opcional",
            "donateLine2": "Se te ajuda, essa é a maior recompensa.",
            "donateScan": "Digitalizar com WeChat",
            "tooltip": "FocusFlow — ativa a última janela do ecrã onde o cursor entra",
        ]),
        Lang(code: "ru", name: "Русский", strings: [
            "enabled": "Включено",
            "accessibility": "Доступ к универсальному доступу",
            "granted": "Разрешено",
            "notGranted": "Не разрешено (нажмите, чтобы разрешить)",
            "launchAtLogin": "Запускать при входе",
            "language": "Язык",
            "version": "Версия",
            "quit": "Выход",
            "donate": "Поддержать",
            "donateLine1": "Программа бесплатна, поддержка по желанию",
            "donateLine2": "Если это помогает — лучшей награды не нужно.",
            "donateScan": "Сканируйте в WeChat",
            "tooltip": "FocusFlow — активирует последнее окно на дисплее, куда попадает курсор",
        ]),
        Lang(code: "vi", name: "Tiếng Việt", strings: [
            "enabled": "Đã bật",
            "accessibility": "Quyền trợ năng",
            "granted": "Đã cấp quyền",
            "notGranted": "Chưa cấp quyền (nhấn để cấp)",
            "launchAtLogin": "Khởi động cùng máy",
            "language": "Ngôn ngữ",
            "version": "Phiên bản",
            "quit": "Thoát",
            "donate": "Ủng hộ",
            "donateLine1": "Phần mềm miễn phí, ủng hộ tùy ý",
            "donateLine2": "Nếu nó giúp ích cho bạn, đó là phần thưởng lớn nhất.",
            "donateScan": "Quét bằng WeChat",
            "tooltip": "FocusFlow — kích hoạt cửa sổ gần nhất trên màn hình mà con trỏ đi vào",
        ]),
    ]

    private static let defaultsKey = "appLanguage"

    static var currentCode: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: defaultsKey),
               languages.contains(where: { $0.code == saved }) {
                return saved
            }
            // 跟随系统首选语言，能匹配到就用，否则英文
            for preferred in Locale.preferredLanguages {
                if let match = languages.first(where: { preferred.hasPrefix($0.code) }) {
                    return match.code
                }
                if preferred.hasPrefix("zh") {
                    return preferred.contains("Hant") || preferred.contains("TW") || preferred.contains("HK")
                        ? "zh-Hant" : "zh-Hans"
                }
                if let base = preferred.split(separator: "-").first,
                   let match = languages.first(where: { $0.code == String(base) }) {
                    return match.code
                }
            }
            return "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    static func t(_ key: String) -> String {
        let lang = languages.first(where: { $0.code == currentCode }) ?? languages[2]
        return lang.strings[key] ?? languages[2].strings[key] ?? key
    }
}
