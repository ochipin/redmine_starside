# =============================================================================
# lib/tasks/redmine_starside.rake
# =============================================================================
# プラグイン削除時に、Redmine コアの settings テーブルへ残る
# 'plugin_redmine_starside' 行を明示的に掃除するためのタスク。
#
# 使い方（アンインストール時）:
#   bundle exec rake redmine_starside:uninstall_settings RAILS_ENV=production
#   bundle exec rake redmine:plugins:migrate NAME=redmine_starside VERSION=0 RAILS_ENV=production
#   # その後 plugins/redmine_starside を削除
#
# 設定行を消し忘れても無害（読む側がいなくなるだけ）。再インストールすれば
# 通常どおり再利用される。
# =============================================================================
namespace :redmine_starside do
  desc 'Remove all redmine_starside plugin settings from the database'
  task uninstall_settings: :environment do
    setting = Setting.find_by(name: 'plugin_redmine_starside')
    if setting
      setting.destroy
      puts '[redmine_starside] plugin settings removed from the database.'
    else
      puts '[redmine_starside] no plugin settings found (nothing to do).'
    end
  end

  desc 'Show current redmine_starside plugin settings (for inspection)'
  task show_settings: :environment do
    setting = Setting.find_by(name: 'plugin_redmine_starside')
    if setting
      puts "[redmine_starside] name=#{setting.name}"
      puts setting.value
    else
      puts '[redmine_starside] no plugin settings stored.'
    end
  end
end
