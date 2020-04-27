#!/bin/bash

######################################################################################
# 请使用管理员身份运行
# SSR #####################################################
# 订阅链接
URL='https://example.com/example'
# local.py位置
SSR_BIN_FILE='/example/local.py'
# 配置文件位置
SSR_CFG_FILE='/example/config.json'
# 端口
SSR_PORT=10808
# HAproxy #################################################
# 配置文件位置
HA_CFG_FILE='/etc/haproxy/haproxy.cfg'
# HAproxy 本地端口
HA_PORT=10800
# HAproxy server option，用于检查各服务器是否在线及断线恢复
PARAM='check inter 500 rise 2 fall 4'
# HAproxy 基本配置，各服务器的配置将会被追加在后面
CONFIG="\
global
	log /dev/log local0
	log /dev/log local1 notice
	chroot /var/lib/haproxy
	user haproxy
	group haproxy

defaults
	log global
	mode tcp
	balance roundrobin
	retries 3
	timeout connect 500
	timeout client 3000
	timeout server 3000

listen server
	bind 0.0.0.0:${HA_PORT}
"
###########################################################
######################################################################################

# （不在末尾填充'='的）base64url 解码
decode(){
	local code=$1
	if [ $(expr ${#code} % 4) == 2 ]
	then
		code=${code}"=="
	elif [ $(expr ${#code} % 4) == 3 ]
	then
		code=${code}"="
	fi
	echo ${code} | base64url -d
}

# 逐行输出如下格式的节点信息
# server&port&protocol&method&obfs&password&paramName1=param1&...
getlink(){
	local data=$(decode $(curl -s ${URL}))
	# local data=$(decode $(cat ./sub))
	if [ -z "${data}" ]
	then
		return 1
	else
		local link
		for link in ${data}
		do
			if [ ${link%://*} = 'ssr' ]
			then
				local nodeinfo=$(decode ${link#*://})
				local password=${nodeinfo##*:}
					password=$(decode ${password%%/?*})
				local params=$(echo ${nodeinfo##*/?} | sed 's/\&/\n/g')
				nodeinfo=$(echo ${nodeinfo%:*} | sed 's/:/\&/g')'&'${password}
				local param
				for param in ${params}
				do
					nodeinfo=${nodeinfo}'&'${param%%=*}'='$(decode ${param#*=})
				done
				echo ${nodeinfo}
			# elif [ ${link%://*} = 'ss' ]
			# then
			#
			# elif [ ${link:0:3} = 'MAX' ]
			# 根据一般约定，当首行为MAX=n时，客户端随机保留n条，（如果有）丢弃多余的
			# 实现麻烦，很少用到，就此略过
			#
			# else
			#
			fi
		done
	fi
	return 0
}

SSRconfig(){
	local config="\
{
	\"server\": \"127.0.0.1\",
	\"server_port\": ${HA_PORT},
	\"password\": \"$4\",
	\"method\": \"$2\",
	\"obfs\": \"$3\",
	\"protocol\": \"$1\",
	\"obfs_param\": \"$5\",
	\"protocol_param\": \"$6\",
	\"local_address\": \"127.0.0.1\",
	\"local_port\": \"${SSR_PORT}\",
	\"timeout\": 300,
	\"workers\": 1
}
"
	echo -e "${config}" > ${SSR_CFG_FILE}
	echo -e "SSR:"
	${SSR_BIN_FILE} -c ${SSR_CFG_FILE} --fast-open -d restart
	echo
}

main(){
	local links=$(getlink)
	if [ $? == 0 ]
	then
		echo "Download: SUCCESS."
	else
		echo "Download: FAILED."
		return
	fi

	local config=${CONFIG}
	local info
	local tag=true
	local identical=true

	local protocol
	local method
	local obfs
	local password
	local obfsparam
	local protoparam

	local proto
	local mthd
	local obfs_t
	local pswd
	local oparam
	local pparam

	local i=1
	links=$(echo -e "$links" | tr '\n' '^')
	while [ -n "$(echo "$links" | cut -d '^' -f ${i})" ]
	do
		local nodeinfo="$(echo "$links" | cut -d '^' -f ${i})"
		# 判断是否是用来通告信息的假节点，一般这种节点会使用10以下的端口
		local port=$(echo ${nodeinfo} | cut -d \& -f 2)
		if [ ${#port} -lt 2 ]
		then # 从中获取通告信息
			local info_t=$(echo ${nodeinfo} | sed 's/.\+remarks=\(.\+\)&.\+/\1/')"\n"
			info=${info}${info_t%%&*}
		else # 判断参数是否一致
			proto=$(echo ${nodeinfo} | cut -d \& -f3)
			mthd=$(echo ${nodeinfo} | cut -d \& -f4)
			obfs_t=$(echo ${nodeinfo} | cut -d \& -f5)
			pswd=$(echo ${nodeinfo} | cut -d \& -f6)
			oparam=$(echo ${nodeinfo} | sed 's/.\+obfsparam=\(.\+\)&.\+/\1/')
				oparam=${oparam%%&*}
			pparam=$(echo ${nodeinfo} | sed 's/.\+protoparam=\(.\+\)&.\+/\1/')
				pparam=${pparam%%&*}

			if [ ${tag} = 'true' ]
			then
				tag=false
				protocol=${proto}
				method=${mthd}
				obfs=${obfs_t}
				password=${pswd}
				obfsparam=${oparam}
				protoparam=${pparam}
			else
				if [ ${protocol} != ${proto} -o ${method} != ${mthd} -o ${obfs} != ${obfs_t} -o ${password} != ${pswd} -o ${obfsparam} != ${oparam} -o ${protoparam} != ${pparam} ]
				then
					identical=false
				fi
			fi
			config=${config}"\tserver s${i} "$(echo ${nodeinfo} | cut -d \& -f1)":"$(echo ${nodeinfo} | cut -d \& -f2)" "${PARAM}"\n"
		fi
		i=$(expr ${i} + 1)
	done
	if [ ${identical} = 'true' ]
	then
		echo -e "${config}" > ${HA_CFG_FILE}
		local restartinfo=$(systemctl restart haproxy)
		if [ -z "${restartinfo}" ]
		then
			echo "HAproxy: SUCCESS."
			SSRconfig ${protocol} ${method} ${obfs} ${password} ${obfsparam} ${protoparam}
		else
			echo "HAproxy: FAILED. Cannot restart haproxy"
			echo "Info:"
			echo -e "${restartinfo}"
		fi
	else
		echo "HAproxy: FAILED. The parameter are not identical, cannot configure HAproxy."
	fi
	echo -e "Subscription Info:\n${info}"
	echo "ALL COMPLETED!"
}

main
