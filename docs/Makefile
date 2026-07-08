.PHONY: html upload default

default: html

html:
	hunim build

upload: html
	rsync -rtvzP --exclude=".DS_Store" --delete ./public "root@hunim.org:/var/www/hunim"

