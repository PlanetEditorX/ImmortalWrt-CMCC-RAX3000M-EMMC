#!/bin/bash
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#

# 移除 ImmortalWrt 源码中自带的旧版 OpenClash
# 官方 feed 中的版本往往更新不及时，会导致版本撕裂报错
rm -rf feeds/luci/applications/luci-app-openclash
# 强制删除 Rust 包目录
rm -rf feeds/packages/lang/rust

# 添加 OpenClash 官方源
git clone --depth=1 -b master https://github.com/vernesong/OpenClash.git package/luci-app-openclash

# 修正权限
# 确保脚本在编译前有正确的执行权限
chmod -R 755 package/luci-app-openclash
