#! /bin/sh
#exec 2>>build.log  ##编译过程打印到日志文件中
## 自动构建，并下载基础文件   .Power by terrfly

#引入config
. ./config.sh

#  需要注意： 
# 1. root用户登录
# 2. 请务必包含  docker环境 和 git环境

# 第0步：提示信息
echo "请确认当前是全新服务器安装,  是否继续？"
echo "(Please confirm if it is a brand new server installation, do you want to continue?)"
echo " [yes/no] ?"
read useryes
if [ -z "$useryes" ] || [ $useryes != 'yes' ]
then
	echo 'good bye'
	exit 0
fi

# 第1步：创建基本目录
echo "[1] 创建项目根目录($rootDir).... "
mkdir $rootDir/nginx -p
mkdir $rootDir/nginx/conf -p
mkdir $rootDir/nginx/conf.d -p
mkdir $rootDir/nginx/html -p
mkdir $rootDir/nginx/logs -p

mkdir $rootDir/mysql -p
mkdir $rootDir/mysql/config -p
mkdir $rootDir/mysql/log -p
mkdir $rootDir/mysql/data -p

# mkdir $rootDir/activemq -p

mkdir $rootDir/redis -p
mkdir $rootDir/redis/config -p
mkdir $rootDir/redis/data -p

mkdir $rootDir/service/configs -p
mkdir $rootDir/service/uploads -p
mkdir $rootDir/service/logs -p

mkdir $rootDir/sources -p
echo "[1] Done. "

# 第2步：拉取项目源代码  || 拉取脚本文件
echo "[2] 拉取项目源代码文件.... "
cd $rootDir/sources
git clone https://gitee.com/jeequan/jeepay.git
echo "[2] Done. "

# 创建一个 bridge网络
docker network create jeepay-net

# 第3步：下载mysql官方镜像 & 启动
echo "[3] 下载并启动mysql容器.... "

# 将Mysql的配置文件复制到对应的映射目录下
cd $currentPath && cp ./include/my.cnf $rootDir/mysql/config/my.cnf

# 镜像启动
docker run -p 3306:3306 --name mysql8 --network=jeepay-net  \
--restart=always --privileged=true \
-v /etc/localtime:/etc/localtime:ro \
-v $rootDir/mysql/log:/var/log/mysql  \
-v $rootDir/mysql/data:/var/lib/mysql  \
-v $rootDir/mysql/config:/etc/mysql  \
-e MYSQL_ROOT_PASSWORD=$mysql_pwd \
-d mysql:8.0.25

# 容器重启
docker restart mysql8

# 避免未启动完成或出现错误： ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock' 
echo "等待重启mysql容器....... "
sleep 10

echo "[3] 初始化数据导入 ...... "
# 创建数据库  && 导入数据
echo "CREATE DATABASE jeepaydb DEFAULT CHARACTER SET utf8mb4" | docker exec -i mysql8 mysql -uroot -p$mysql_pwd
docker exec -i mysql8 sh -c "mysql -uroot -p$mysql_pwd --default-character-set=utf8mb4  jeepaydb" < $rootDir/sources/jeepay/docs/sql/init.sql

echo "[3] Done. "

# 第4步：下载redis官方镜像 & 启动
echo "[4] 下载并启动redis容器.... "

# 将配置文件复制到对应的映射目录下
cd $currentPath && cp ./include/redis.conf $rootDir/redis/config/redis.conf

# 镜像启动
docker run -p 6379:6379 --name redis6 --network=jeepay-net  \
--restart=always --privileged=true \
-v /etc/localtime:/etc/localtime:ro \
-v $rootDir/redis/config/redis.conf:/etc/redis/redis.conf \
-v $rootDir/redis/data:/data \
-d redis:6.2.14 redis-server /etc/redis/redis.conf


echo "[4] Done. "


# 第5步：下载并启动activemq容器
echo "[5] 下载并启动activemq容器.... "

docker run -p 8161:8161 -p 61616:61616 --name activemq5 --network=jeepay-net \
--restart=always \
-v /etc/localtime:/etc/localtime:ro \
-d jeepay/activemq:5.15.16


echo "[5] Done. "


# 第6步：下载并启动 java 项目 

# 复制java配置文件
cd $rootDir/service/configs/ && cp -r $rootDir/sources/jeepay/conf/* .


echo "[6.1] 下载并启动 java 项目 [ jeepaymanager  ] .... "
# 运行 java项目
docker run -itd --name jeepaymanager --network=jeepay-net \
-p 9217:9217 \
-v $rootDir/service/logs:/jeepayhomes/service/logs \
-v $rootDir/service/uploads:/jeepayhomes/service/uploads \
-v $rootDir/service/configs/manager/application.yml:/jeepayhomes/service/app/application.yml \
-d jeepay/jeepay-manager:v2.2.2

echo "[6.2] 下载并启动 java 项目 [ jeepaymerchant  ] .... "
# 运行 java项目
docker run -itd --name jeepaymerchant --network=jeepay-net \
-p 9218:9218 \
-v $rootDir/service/logs:/jeepayhomes/service/logs \
-v $rootDir/service/uploads:/jeepayhomes/service/uploads \
-v $rootDir/service/configs/merchant/application.yml:/jeepayhomes/service/app/application.yml \
-d jeepay/jeepay-merchant:v2.2.2

echo "[6.3] 下载并启动 java 项目 [ jeepaypayment  ] .... "
# 运行 java项目
docker run -itd --name jeepaypayment --network=jeepay-net \
-p 9216:9216 \
-v $rootDir/service/logs:/jeepayhomes/service/logs \
-v $rootDir/service/uploads:/jeepayhomes/service/uploads \
-v $rootDir/service/configs/payment/application.yml:/jeepayhomes/service/app/application.yml \
-d jeepay/jeepay-payment:v2.2.2

echo "[6] Done. "


echo "[7] 下载并启动 nginx .... "

cd $rootDir/nginx/html
wget https://gitee.com/jeequan/jeepay-ui/releases/download/v1.10.0/html.tar.gz
tar -vxf html.tar.gz

# 将配置文件复制到对应的映射目录下
cd $currentPath && cp ./include/nginx.conf $rootDir/nginx/conf/nginx.conf


docker run --name nginx118  \
--restart=always --privileged=true --net=host \
-v /etc/localtime:/etc/localtime:ro \
-v $rootDir/nginx/conf/nginx.conf:/etc/nginx/nginx.conf \
-v $rootDir/nginx/conf/conf.d:/etc/nginx/conf.d \
-v $rootDir/nginx/logs:/var/log/nginx \
-v $rootDir/nginx/html:/usr/share/nginx/html \
-d nginx:1.18.0

echo "[7] Done. "

docker logs -f jeepaypayment

