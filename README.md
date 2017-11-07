# GroupMap                                                                                                                                         
                                                                                                                                                   
Find your peeps on a map.                                                                                                                          
                                                                                                                                                   
## Install                                                                                                                                         
                                                                                                                                                   
```
apt-get install ruby ruby-slim ruby-sinatra

git clone https://github.com/Furikuda/groupmap/
ruby index.rb
```
## Add a map
First, get vipz
```
apt-get install libvips-tools
```

Get a big pic, and build the tiles pyramid
```
wget http://big/pic.jpg
vips dzsave pic.jpg  --layout google --tile-size 256  my-big-pic
```
Then move it to the public/group_pics folder
```
mv my-big-pic public/group_pics
```
and restart the webserver.
