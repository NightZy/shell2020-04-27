# 用于自动更新订阅并配置HAproxy负载均衡的脚本

## 依赖的主要命令/程序
* base64url
* curl
* systemctl
* HAproxy
* 某上网工具
## 用法
1. 编辑tool.sh中的配置项
2. 给与执行权限
3. 使用root用户（或用sudo）运行
## 注意
* 该脚本在我的 debian 10 上测试通过，没有进行过其他测试
* 仅学习使用
* 欢迎一起交流学习
## 更新
### 2020/04/30
1. 使用 HAproxy 的 resolvers section，解决服务器域名不可解析时，HAproxy 服务不能启动的问题。
2. 优化 HAproxy 配置文件写法。
