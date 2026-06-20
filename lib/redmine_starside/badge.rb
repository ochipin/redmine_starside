# frozen_string_literal: true

require 'cgi'  # HTML エンティティ復元（CGI.unescapeHTML）用
require 'erb'  # URL パスセグメント安全化（ERB::Util.url_encode）用
require 'zlib' # 未定義キーの色選択を安定させる CRC32 用

# =============================================================================
# RedmineStarside::Badge
# =============================================================================
# バッジマクロの中核ロジック。
#
#   - DEFINITIONS         : コードが持つデフォルト定義（常に「正」）
#   - effective_definitions : DEFINITIONS に DB 設定(overrides/custom)を
#                             防御的にマージした「実効定義」
#
# 設計方針（バージョンアップ耐性）:
#   * DB には「変更点だけ」を保存する。全量は保存しない。
#       overrides : 既存キーの色だけを上書き { "redmine" => "FF0000" }
#       custom    : 新規追加バッジ           { "foo" => {label,color,logo,logo_color} }
#   * 読み出しは必ず「コード(最新) を土台に、DB の差分を上載せ」する向き。
#     → プラグイン更新でデフォルトを改善すれば、ユーザーが触っていない
#       キーは自動で最新に追従する。
#   * DB の値は信用しない。型・hex 妥当性を検査し、壊れていれば黙って捨てて
#     デフォルトに落ちる。例外で Wiki 描画を止めない。
# =============================================================================
module RedmineStarside
  module Badge
    DEFAULT_BASE_URL = 'https://img.shields.io'

    # 16進カラー（3/4/6/8桁）の妥当性
    HEX_RE = /\A[0-9A-Fa-f]{3,4}\z|\A[0-9A-Fa-f]{6}\z|\A[0-9A-Fa-f]{8}\z/

    # 未定義キー用のフォールバック色パレット。
    # 白背景で視認性が高く、白文字も読める中濃度の色を、既存ブランドカラー
    # （赤・ピンク・紫・藍・青・シアン・緑・黄／オリーブ・橙・灰・茶）に
    # 寄せて選定。fallback_color がキー名から決定的にこの中から 1 色を選ぶ。
    FALLBACK_COLORS = %w[
      C62828 AD1457 6A1B9A 4527A0 283593
      1565C0 0277BD 00838F 00695C 2E7D32
      558B2F 9E7D0A EF6C00 546E7A 5D4037
    ].freeze

    # この会話で決めてきたアイコンのカラーリング（デフォルト・コードが正）
    DEFINITIONS = {
      # OS / Distribution
      'linux'      => { label: 'Linux',             color: 'FCC624', logo: 'linux',          logo_color: 'black' },
      'ubuntu'     => { label: 'Ubuntu',            color: 'E95420', logo: 'ubuntu' },
      'debian'     => { label: 'Debian',            color: 'A81D33', logo: 'debian' },
      'redhat'     => { label: 'Red Hat',           color: 'EE0000', logo: 'redhat' },
      'rocky'      => { label: 'Rocky Linux',       color: '10B981', logo: 'rockylinux' },
      'rockylinux' => { label: 'Rocky Linux',       color: '10B981', logo: 'rockylinux' },
      'alma'       => { label: 'AlmaLinux',         color: '000000', logo: 'almalinux' },
      'almalinux'  => { label: 'AlmaLinux',         color: '000000', logo: 'almalinux' },
      'alpine'     => { label: 'Alpine Linux',      color: '0D597F', logo: 'alpinelinux' },
      # Container / Orchestration
      'docker'     => { label: 'Docker',            color: '2496ED', logo: 'docker' },
      'kubernetes' => { label: 'Kubernetes',        color: '326CE5', logo: 'kubernetes' },
      'k8s'        => { label: 'Kubernetes',        color: '326CE5', logo: 'kubernetes' },
      # Web server
      'nginx'      => { label: 'Nginx',             color: '009639', logo: 'nginx' },
      'apache'     => { label: 'Apache',            color: 'D22128', logo: 'apache' },
      # Browser
      'firefox'    => { label: 'Firefox',           color: 'FF7139', logo: 'firefoxbrowser' },
      'chrome'     => { label: 'Chrome',            color: '4285F4', logo: 'googlechrome' },
      'ie'         => { label: 'Internet Explorer', color: '0076D6', logo: 'internetexplorer' },
      # Language
      'c'          => { label: 'C',                 color: 'A8B9CC', logo: 'c',          logo_color: 'black' },
      'cpp'        => { label: 'C++',               color: '00599C', logo: 'cplusplus' },
      'cplusplus'  => { label: 'C++',               color: '00599C', logo: 'cplusplus' },
      'fortran'    => { label: 'Fortran',           color: '734F96', logo: 'fortran' },
      'java'       => { label: 'Java',              color: '007396', logo: 'openjdk' },
      'openjdk'    => { label: 'Java',              color: '007396', logo: 'openjdk' },
      'go'         => { label: 'Go',                color: '00ADD8', logo: 'go' },
      'golang'     => { label: 'Go',                color: '00ADD8', logo: 'go' },
      'rust'       => { label: 'Rust',              color: '000000', logo: 'rust' },
      'perl'       => { label: 'Perl',              color: '39457E', logo: 'perl' },
      'ruby'       => { label: 'Ruby',              color: 'CC342D', logo: 'ruby' },
      'python'     => { label: 'Python',            color: '3776AB', logo: 'python' },
      'clojure'    => { label: 'Clojure',           color: '5881D8', logo: 'clojure' },
      'javascript' => { label: 'JavaScript',        color: 'F7DF1E', logo: 'javascript', logo_color: 'black' },
      'js'         => { label: 'JavaScript',        color: 'F7DF1E', logo: 'javascript', logo_color: 'black' },
      'html'       => { label: 'HTML5',             color: 'E34F26', logo: 'html5' },
      'html5'      => { label: 'HTML5',             color: 'E34F26', logo: 'html5' },
      'css'        => { label: 'CSS3',              color: '1572B6', logo: 'css3' },
      'css3'       => { label: 'CSS3',              color: '1572B6', logo: 'css3' },
      'bash'       => { label: 'Bash',              color: '4EAA25', logo: 'gnubash' },
      'shell'      => { label: 'Bash',              color: '4EAA25', logo: 'gnubash' },
      # DB
      'postgresql' => { label: 'PostgreSQL',        color: '4169E1', logo: 'postgresql' },
      'postgres'   => { label: 'PostgreSQL',        color: '4169E1', logo: 'postgresql' },
      'mariadb'    => { label: 'MariaDB',           color: '003545', logo: 'mariadb' },
      'mysql'      => { label: 'MySQL',             color: '4479A1', logo: 'mysql' },
      'sqlite'     => { label: 'SQLite',            color: '003B57', logo: 'sqlite' },
      # CMS / Docs / Tools
      'redmine'    => { label: 'Redmine',           color: 'B32024', logo: 'redmine' },
      'rundeck'    => { label: 'Rundeck',           color: 'F73F39', logo: 'rundeck' },
      'mattermost' => { label: 'Mattermost',        color: '0058CC', logo: 'mattermost' },
      'drupal'     => { label: 'Drupal',            color: '0678BE', logo: 'drupal' },
      'wordpress'  => { label: 'WordPress',         color: '21759B', logo: 'wordpress' },
      'hugo'       => { label: 'Hugo',              color: 'FF4088', logo: 'hugo' },

      # --- Language (追加) ---
      'php'        => { label: 'PHP',               color: '777BB4', logo: 'php' },
      'typescript' => { label: 'TypeScript',        color: '3178C6', logo: 'typescript' },
      'ts'         => { label: 'TypeScript',        color: '3178C6', logo: 'typescript' },

      # --- OS / Distribution (追加) ---
      'mint'       => { label: 'Linux Mint',        color: '87CF3E', logo: 'linuxmint' },
      'linuxmint'  => { label: 'Linux Mint',        color: '87CF3E', logo: 'linuxmint' },
      'fedora'     => { label: 'Fedora',            color: '51A2DA', logo: 'fedora' },
      'opensuse'   => { label: 'openSUSE',          color: '73BA25', logo: 'opensuse' },
      'suse'       => { label: 'SUSE',              color: '0C322C', logo: 'suse' },
      'zorin'      => { label: 'Zorin OS',          color: '15A6F0', logo: 'zorin' },
      'freebsd'    => { label: 'FreeBSD',           color: 'AB2B28', logo: 'freebsd' },
      'bsd'        => { label: 'FreeBSD',           color: 'AB2B28', logo: 'freebsd' },
      'apple'      => { label: 'Apple',             color: '000000', logo: 'apple' },
      'macos'      => { label: 'macOS',             color: '000000', logo: 'apple' },

      # --- Virtualization / Storage (追加) ---
      'proxmox'    => { label: 'Proxmox',           color: 'E57000', logo: 'proxmox' },
      'ceph'       => { label: 'Ceph',              color: 'EF5C55', logo: 'ceph' },

      # --- Git / CI / IaC (追加) ---
      'git'        => { label: 'Git',               color: 'F05032', logo: 'git' },
      'github'     => { label: 'GitHub',            color: '181717', logo: 'github' },
      'gitlab'     => { label: 'GitLab',            color: 'FC6D26', logo: 'gitlab' },
      'ansible'    => { label: 'Ansible',           color: 'EE0000', logo: 'ansible' },
      'terraform'  => { label: 'Terraform',         color: '844FBA', logo: 'terraform' },

      # --- Secrets / Auth / Observability (追加) ---
      'vault'      => { label: 'Vault',             color: 'FFEC6E', logo: 'vault',      logo_color: 'black' },
      'openbao'    => { label: 'OpenBao',           color: '1D2D44', logo: 'openbao' },
      'keycloak'   => { label: 'Keycloak',          color: '4D4D4D', logo: 'keycloak' },
      'prometheus' => { label: 'Prometheus',        color: 'E6522C', logo: 'prometheus' },
      'grafana'    => { label: 'Grafana',           color: 'F46800', logo: 'grafana' },
      'elasticsearch' => { label: 'Elasticsearch',  color: '005571', logo: 'elasticsearch' },
      'superset'   => { label: 'Apache Superset',   color: '20A7C9', logo: 'apachesuperset' },

      # --- Build / Package / AI tools (追加) ---
      'npm'        => { label: 'npm',               color: 'CB3837', logo: 'npm' },
      'ollama'     => { label: 'Ollama',            color: '000000', logo: 'ollama' },
      'make'       => { label: 'Make',              color: '6D00CC', logo: 'make' },
      'gnumake'    => { label: 'Make',              color: '6D00CC', logo: 'make' },

      # --- Google Workspace (追加) ---
      'docs'        => { label: 'Google Docs',      color: '4285F4', logo: 'googledocs' },
      'sheets'      => { label: 'Google Sheets',    color: '34A853', logo: 'googlesheets' },
      'slides'      => { label: 'Google Slides',    color: 'FBBC04', logo: 'googleslides', logo_color: 'black' },
      'forms'       => { label: 'Google Forms',     color: '7248B9', logo: 'googleforms' },
      'drive'       => { label: 'Google Drive',     color: '4285F4', logo: 'googledrive' },

      # --- MS 製品名エイリアス（実体は Google Workspace に委譲） ---
      # 商標回避のため、ロゴ・ラベルとも Google 側を表示する。
      'word'        => { label: 'Google Docs',      color: '4285F4', logo: 'googledocs' },
      'spreadsheet' => { label: 'Google Sheets',    color: '34A853', logo: 'googlesheets' },
      'excel'       => { label: 'Google Sheets',    color: '34A853', logo: 'googlesheets' },
      'powerpoint'  => { label: 'Google Slides',    color: 'FBBC04', logo: 'googleslides', logo_color: 'black' },
      'ppt'         => { label: 'Google Slides',    color: 'FBBC04', logo: 'googleslides', logo_color: 'black' },

      # --- Generic icons (埋め込み SVG。logo は EMBEDDED_LOGOS のマーカー) ---
      # アイコン出典: Material Symbols (Apache License 2.0)
      'settings'    => { label: 'Settings',          color: '607D8B', logo: 'settings' },
      'maintenance' => { label: 'Maintenance',       color: 'F9A825', logo: 'maintenance', logo_color: 'black' },
      'bug'         => { label: 'Bug',               color: 'E53935', logo: 'bug' },
      'network'     => { label: 'Network',           color: '1E88E5', logo: 'network' }
    }.freeze

    # =========================================================================
    # 埋め込み SVG ロゴ（方式C）
    # -------------------------------------------------------------------------
    # Simple Icons に無い／自作の汎用アイコンを、Base64 SVG として内部に持つ。
    # DEFINITIONS 側は logo に短いマーカー名（'settings' 等）を置き、url_for が
    # ここを参照して data URL に展開する。これにより:
    #   - DEFINITIONS が長大な Base64 で汚れない
    #   - shields.io の Simple Icons 収録可否に依存しない
    #   - 将来 90 個のローカル SVG 同梱もこの仕組みに乗せられる
    #
    # 値は data URL の base64 部分のみ（"data:image/svg+xml;base64," は付けない）。
    # SVG は単色（fill=white 等）で持ち、背景色に映えるようにしておく。
    #
    # 出典 / ライセンス:
    #   settings, maintenance, bug, network … Material Symbols (Apache-2.0)
    # =========================================================================
    EMBEDDED_LOGOS = {
      'settings'    => 'PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGhlaWdodD0iMjRweCIgdmlld0JveD0iMCAtOTYwIDk2MCA5NjAiIHdpZHRoPSIyNHB4IiBmaWxsPSJ3aGl0ZSI+PHBhdGggZD0ibTM3MC04MC0xNi0xMjhxLTEzLTUtMjQuNS0xMlQzMDctMjM1bC0xMTkgNTBMNzgtMzc1bDEwMy03OHEtMS03LTEtMTMuNXYtMjdxMC02LjUgMS0xMy41TDc4LTU4NWwxMTAtMTkwIDExOSA1MHExMS04IDIzLTE1dDI0LTEybDE2LTEyOGgyMjBsMTYgMTI4cTEzIDUgMjQuNSAxMnQyMi41IDE1bDExOS01MCAxMTAgMTkwLTEwMyA3OHExIDcgMSAxMy41djI3cTAgNi41LTIgMTMuNWwxMDMgNzgtMTEwIDE5MC0xMTgtNTBxLTExIDgtMjMgMTV0LTI0IDEyTDU5MC04MEgzNzBabTcwLTgwaDc5bDE0LTEwNnEzMS04IDU3LjUtMjMuNVQ2MzktMzI3bDk5IDQxIDM5LTY4LTg2LTY1cTUtMTQgNy0yOS41dDItMzEuNXEwLTE2LTItMzEuNXQtNy0yOS41bDg2LTY1LTM5LTY4LTk5IDQycS0yMi0yMy00OC41LTM4LjVUNTMzLTY5NGwtMTMtMTA2aC03OWwtMTQgMTA2cS0zMSA4LTU3LjUgMjMuNVQzMjEtNjMzbC05OS00MS0zOSA2OCA4NiA2NHEtNSAxNS03IDMwdC0yIDMycTAgMTYgMiAzMXQ3IDMwbC04NiA2NSAzOSA2OCA5OS00MnEyMiAyMyA0OC41IDM4LjVUNDI3LTI2NmwxMyAxMDZabTQyLTE4MHE1OCAwIDk5LTQxdDQxLTk5cTAtNTgtNDEtOTl0LTk5LTQxcS01OSAwLTk5LjUgNDFUMzQyLTQ4MHEwIDU4IDQwLjUgOTl0OTkuNSA0MVptLTItMTQwWiIvPjwvc3ZnPg==',
      'maintenance' => 'PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGhlaWdodD0iMjRweCIgdmlld0JveD0iMCAtOTYwIDk2MCA5NjAiIHdpZHRoPSIyNHB4IiBmaWxsPSJ3aGl0ZSI+PHBhdGggZD0iTTczOS04My41cS03LTIuNS0xMy04LjVMNTIyLTI5NnEtNi02LTguNS0xM3QtMi41LTE1cTAtOCAyLjUtMTV0OC41LTEzbDg1LTg1cTYtNiAxMy04LjV0MTUtMi41cTggMCAxNSAyLjV0MTMgOC41bDIwNCAyMDRxNiA2IDguNSAxM3QyLjUgMTVxMCA4LTIuNSAxNXQtOC41IDEzbC04NSA4NXEtNiA2LTEzIDguNVQ3NTQtODFxLTggMC0xNS0yLjVabS01NDkuNS41cS03LjUtMy0xMy41LTlsLTg0LTg0cS02LTYtOS0xMy41VDgwLTIwNXEwLTggMy0xNXQ5LTEzbDIxMi0yMTJoODVsMzQtMzQtMTY1LTE2NWgtNTdMODAtNzY1bDExMy0xMTMgMTIxIDEyMXY1N2wxNjUgMTY1IDExNi0xMTYtNDMtNDMgNTYtNTZINDk1bC0yOC0yOCAxNDItMTQyIDI4IDI4djExM2w1Ni01NiAxNDIgMTQycTE3IDE3IDI2IDM4LjV0OSA0NS41cTAgMjQtOSA0NnQtMjYgMzlsLTg1LTg1LTU2IDU2LTQyLTQyLTIwNyAyMDd2ODRMMjMzLTkycS02IDYtMTMgOXQtMTUgM3EtOCAwLTE1LjUtM1oiLz48L3N2Zz4=',
      'bug'         => 'PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGhlaWdodD0iMjRweCIgdmlld0JveD0iMCAtOTYwIDk2MCA5NjAiIHdpZHRoPSIyNHB4IiBmaWxsPSJ3aGl0ZSI+PHBhdGggZD0iTTQ4MC0xMjBxLTY1IDAtMTIwLjUtMzJUMjcyLTI0MEgxNjB2LTgwaDg0cS0zLTIwLTMuNS00MHQtLjUtNDBoLTgwdi04MGg4MHEwLTIwIC41LTQwdDMuNS00MGgtODR2LTgwaDExMnExNC0yMyAzMS41LTQzdDQwLjUtMzVsLTY0LTY2IDU2LTU2IDg2IDg2cTI4LTkgNTctOXQ1NyA5bDg4LTg2IDU2IDU2LTY2IDY2cTIzIDE1IDQxLjUgMzQuNVQ2ODgtNjQwaDExMnY4MGgtODRxMyAyMCAzLjUgNDB0LjUgNDBoODB2ODBoLTgwcTAgMjAtLjUgNDB0LTMuNSA0MGg4NHY4MEg2ODhxLTMyIDU2LTg3LjUgODhUNDgwLTEyMFptLTgwLTIwMGgxNjB2LTgwSDQwMHY4MFptMC0xNjBoMTYwdi04MEg0MDB2ODBaIi8+PC9zdmc+',
      'network'     => 'PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGhlaWdodD0iMjRweCIgdmlld0JveD0iMCAtOTYwIDk2MCA5NjAiIHdpZHRoPSIyNHB4IiBmaWxsPSJ3aGl0ZSI+PHBhdGggZD0iTTEyMS0xMjFxLTQxLTQxLTQxLTk5dDQxLTk5cTQxLTQxIDk5LTQxIDE4IDAgMzUgNC41dDMyIDEyLjVsMTUzLTE1M3YtMTEwcS00NC0xMy03Mi00OS41VDM0MC03NDBxMC01OCA0MS05OXQ5OS00MXE1OCAwIDk5IDQxdDQxIDk5cTAgNDgtMjggODQuNVQ1MjAtNjA2djExMGwxNTQgMTUzcTE1LTggMzEuNS0xMi41VDc0MC0zNjBxNTggMCA5OSA0MXQ0MSA5OXEwIDU4LTQxIDk5dC05OSA0MXEtNTggMC05OS00MXQtNDEtOTlxMC0xOCA0LjUtMzV0MTIuNS0zMkw0ODAtNDI0IDM0My0yODdxOCAxNSAxMi41IDMydDQuNSAzNXEwIDU4LTQxIDk5dC05OSA0MXEtNTggMC05OS00MVptNjYxLjUtNTYuNVE4MDAtMTk1IDgwMC0yMjB0LTE3LjUtNDIuNVE3NjUtMjgwIDc0MC0yODB0LTQyLjUgMTcuNVE2ODAtMjQ1IDY4MC0yMjB0MTcuNSA0Mi41UTcxNS0xNjAgNzQwLTE2MHQ0Mi41LTE3LjVabS0yNjAtNTIwUTU0MC03MTUgNTQwLTc0MHQtMTcuNS00Mi41UTUwNS04MDAgNDgwLTgwMHQtNDIuNSAxNy41UTQyMC03NjUgNDIwLTc0MHQxNy41IDQyLjVRNDU1LTY4MCA0ODAtNjgwdDQyLjUtMTcuNVptLTI2MCA1MjBRMjgwLTE5NSAyODAtMjIwdC0xNy41LTQyLjVRMjQ1LTI4MCAyMjAtMjgwdC00Mi41IDE3LjVRMTYwLTI0NSAxNjAtMjIwdDE3LjUgNDIuNVExOTUtMTYwIDIyMC0xNjB0NDIuNS0xNy41WiIvPjwvc3ZnPg=='
    }.freeze

    module_function

    # プラグイン設定 Hash を安全に取得（無ければ空 Hash）
    def settings
      s = Setting.plugin_redmine_starside
      s.is_a?(Hash) ? s : {}
    rescue StandardError
      {}
    end

    # キー正規化（小文字・前後空白除去）
    def normalize_key(key)
      key.to_s.strip.downcase
    end

    # 未定義キー用の色を「キー名から決定的に」選ぶ。
    # 同じキーなら常に同じ色（ページ再読込や shields キャッシュで色が揺れない）、
    # 異なるキーなら散らばって見える。Ruby の String#hash はプロセス毎に
    # 変わってしまうため、安定する CRC32 を使う。
    def fallback_color(key)
      idx = Zlib.crc32(normalize_key(key)) % FALLBACK_COLORS.size
      FALLBACK_COLORS[idx]
    end

    # 色文字列の正規化。先頭 '#' を許容して除去。妥当な hex のみ返し、
    # 不正なら nil。
    def sanitize_color(value)
      v = value.to_s.strip.sub(/\A#/, '')
      v =~ HEX_RE ? v.upcase : nil
    end

    # logo slug の正規化。Simple Icons slug は英数字とハイフン程度。
    # 安全のため許可文字を絞る。空や不正は nil（=ロゴなし）。
    def sanitize_logo(value)
      v = value.to_s.strip.downcase
      return nil if v.empty?
      v =~ /\A[a-z0-9][a-z0-9.\-]*\z/ ? v : nil
    end

    # logo_color は white / black のみ許可。既定 white。
    def sanitize_logo_color(value)
      v = value.to_s.strip.downcase
      %w[white black].include?(v) ? v : 'white'
    end

    # ラベルの正規化。空なら nil。長すぎる入力は切り詰め。
    def sanitize_label(value)
      v = value.to_s.strip
      return nil if v.empty?
      v[0, 64]
    end

    # -------------------------------------------------------------------------
    # 実効定義: DEFINITIONS（最新）を土台に、DB の custom→overrides を防御的に
    # 上載せ。壊れたデータは黙って捨てる。
    # -------------------------------------------------------------------------
    def effective_definitions
      defs = {}
      DEFINITIONS.each { |k, v| defs[k] = v.dup }

      s = settings

      # custom: 新規追加バッジ。期待構造かつ color 妥当のものだけ採用。
      #
      # 2 つの形を受け付ける（設定フォームは連番インデックスで送るため）:
      #   キー名形式 : { "clamav" => {label,color,logo,logo_color} }
      #   連番形式   : { "0" => {key:"clamav", label,color,logo,logo_color}, ... }
      # 連番形式では各値の "key" を実キーとして使う。
      custom = s['custom']
      if custom.is_a?(Hash)
        custom.each do |raw_key, raw_val|
          next unless raw_val.is_a?(Hash)

          # 連番形式なら raw_val['key'] を、そうでなければ raw_key を採用
          key_source = raw_val.key?('key') || raw_val.key?(:key) ? (raw_val['key'] || raw_val[:key]) : raw_key
          key = normalize_key(key_source)
          next if key.empty?

          color = sanitize_color(raw_val['color'] || raw_val[:color])
          next unless color # 色が不正・空の custom は無視（空行スキップも兼ねる）

          label = sanitize_label(raw_val['label'] || raw_val[:label]) || key
          logo  = sanitize_logo(raw_val['logo'] || raw_val[:logo])
          lcol  = sanitize_logo_color(raw_val['logo_color'] || raw_val[:logo_color])

          defs[key] = { label: label, color: color, logo: logo, logo_color: lcol }
        end
      end

      # overrides: 既存（DEFINITIONS or custom 由来）の色だけ上書き。
      overrides = s['overrides']
      if overrides.is_a?(Hash)
        overrides.each do |raw_key, raw_color|
          key = normalize_key(raw_key)
          next unless defs.key?(key) # コードにもカスタムにも無いキーは無視
          color = sanitize_color(raw_color)
          next unless color
          defs[key] = defs[key].merge(color: color)
        end
      end

      defs
    end

    # -------------------------------------------------------------------------
    # ベース URL（絶対 URL / ルート相対パス両対応。リバプロ向け）
    #   (空)                         -> DEFAULT_BASE_URL
    #   "https://localhost/shields/" -> "https://localhost/shields"
    #   "/shields" "shields" "/shields/" -> "/shields"
    #   "/" "//"                     -> ""  (=> "/badge/...")
    # -------------------------------------------------------------------------
    def base_url
      url = settings['badge_base_url'].to_s.strip
      return DEFAULT_BASE_URL if url.empty?

      if url =~ %r{\Ahttps?://}i
        url.sub(%r{/+\z}, '')
      else
        stripped = url.sub(%r{\A/+}, '').sub(%r{/+\z}, '')
        stripped.empty? ? '' : "/#{stripped}"
      end
    end

    # 末尾 "+" を ".*" に。空・nil は nil。
    def normalize_version(raw)
      return nil if raw.nil?
      v = raw.to_s.strip
      return nil if v.empty?
      v.sub(/\+\z/, '.*')
    end

    # HTML エンティティを実文字へ復元する（&#x2605; -> ★, &amp; -> & など）。
    def decode_entities(text)
      CGI.unescapeHTML(text.to_s)
    end

    # shields.io メッセージ部のエスケープ ("_"->"__", "-"->"--", " "->"_")
    def shields_escape(text)
      text.to_s.gsub('_', '__').gsub('-', '--').gsub(' ', '_')
    end

    def encode_segment(text)
      ERB::Util.url_encode(shields_escape(decode_entities(text)))
    end

    # logo 値を shields.io の logo= に渡せる形へ解決する。
    #   - EMBEDDED_LOGOS にマーカーがあれば data URL に展開
    #   - 既に "data:" で始まるならそのまま
    #   - それ以外は Simple Icons slug としてそのまま
    # ロゴ無し(nil/空)は nil を返す。
    def resolve_logo(logo)
      return nil if logo.to_s.empty?
      l = logo.to_s
      if EMBEDDED_LOGOS.key?(l)
        "data:image/svg+xml;base64,#{EMBEDDED_LOGOS[l]}"
      else
        l
      end
    end

    # key, version, color から <img> 用 URL を生成
    def url_for(key, version_raw = nil, color_override = nil, allow_fallback: false)
      d = effective_definitions[normalize_key(key)]
      if d.nil?
        return nil unless allow_fallback
        label_text = key.to_s.strip
        return nil if label_text.empty?
        d = { label: label_text, color: fallback_color(key), logo: nil, logo_color: 'white' }
      end

      color      = sanitize_color(color_override) || d[:color]
      label      = encode_segment(d[:label])
      ver        = normalize_version(version_raw)
      message    = "#{label}-#{color}"
      logo_color = "#{d[:logo_color] || 'white'}"
      if ver
        message    = "#{label}-#{encode_segment(ver)}-#{color}"
        logo_color = 'white'
      end

      path  = "#{base_url}/badge/#{message}"
      logo  = resolve_logo(d[:logo])
      return path if logo.nil?
      "#{path}?logo=#{logo}&logoColor=#{logo_color}"
    end

    # alt 文字列（バージョン併記）
    def alt_for(key, version_raw = nil)
      d = effective_definitions[normalize_key(key)]
      base = d ? d[:label] : key.to_s
      ver  = normalize_version(version_raw)
      ver ? "#{base} #{ver}" : base
    end

    # 設定画面プレビュー用: 実効定義をソートして配列で返す
    def sorted_keys
      effective_definitions.keys.sort
    end

    # -------------------------------------------------------------------------
    # 補完用検索。query を含むキーを部分一致で絞り、前方一致を優先して並べる。
    #
    #   search('d') => docker, debian, ... (前方一致) → word, spreadsheet ...
    #                  (部分一致) の順
    #
    # 返り値は補完UI(Monaco 等)が使いやすい Hash 配列:
    #   { key:, label:, color:, url: }
    #
    # query が空の場合は全件（前方一致なしなのでキー名順）。
    # limit で件数を制限（既定 50。0 以下なら無制限）。
    # -------------------------------------------------------------------------
    def search(query = nil, limit = 50)
      defs = effective_definitions
      q = query.to_s.strip.downcase

      keys =
        if q.empty?
          defs.keys.sort
        else
          matched = defs.keys.select { |k| k.include?(q) }
          # 前方一致(0)→部分一致(1) で層化し、各層内はキー名昇順
          matched.sort_by { |k| [k.start_with?(q) ? 0 : 1, k] }
        end

      keys = keys.first(limit) if limit.to_i.positive?

      keys.map do |k|
        d = defs[k]
        { key: k, label: d[:label], color: d[:color], url: url_for(k) }
      end
    end
  end
end
