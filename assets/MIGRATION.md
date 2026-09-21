# 从官方 audiobookshelf deb 迁移到本包（TOS 版）

本包（TOS 应用中心版）与上游官方 deb **同名**（`audiobookshelf`），dpkg 会将其视为
官方包的升级版本。两者布局不同：

| | 官方 deb | 本包（TOS 版） |
|---|---|---|
| 程序 | `/usr/share/audiobookshelf/audiobookshelf` | `/usr/local/audiobookshelf/bin/audiobookshelf` |
| 配置数据 | `/usr/share/audiobookshelf/config` | `/var/lib/audiobookshelf/config` |
| 元数据 | `/usr/share/audiobookshelf/metadata` | `/var/lib/audiobookshelf/metadata` |
| 监听 | `0.0.0.0:13378` | `127.0.0.1:13378`（回环，经 TOS nginx 访问） |
| 环境文件 | `/etc/default/audiobookshelf` | `/usr/local/audiobookshelf/audiobookshelf.env` |

升级安装后，旧数据 **不会** 被自动迁移（也不会被删除）。如需沿用旧数据：

```bash
# 1. 停服务
systemctl stop audiobookshelf

# 2. 备份旧数据（防手滑）
cp -a /usr/share/audiobookshelf/config /root/abs-config.bak
cp -a /usr/share/audiobookshelf/metadata /root/abs-metadata.bak

# 3. 迁移（仅当 /var/lib/audiobookshelf 下还是空库时执行）
cp -a /usr/share/audiobookshelf/config/. /var/lib/audiobookshelf/config/
cp -a /usr/share/audiobookshelf/metadata/. /var/lib/audiobookshelf/metadata/
chown -R audiobookshelf:audiobookshelf /var/lib/audiobookshelf

# 4. 重启并验证
systemctl start audiobookshelf
curl -sI http://127.0.0.1:13378/audiobookshelf/
```

迁移确认无误后，可删除 `/usr/share/audiobookshelf` 残留与 `/etc/default/audiobookshelf`
（本包不读取该文件）。

> 注意：官方 deb 的环境文件里若设置过 `PORT`/`HOST`/`CONFIG_PATH`/`METADATA_PATH`，
> 本包一律以 systemd unit 里写死的参数为准（安全设计：仅回环监听）。
