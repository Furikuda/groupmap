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
mkdir myconvention; cd myconvention
wget http://big/pic.jpg
vips dzsave pic.jpg  --layout google --tile-size 256  my-big-pic
```
You then might want to add some metadata about the group pic. Make a new file names manifest.json, that looks like this!
```
{
    "name": "My Con 88",
    "shortname": "MC 88",
    "year": "2088",
    "url": "https://my.con/88",
    "source_pic": "pic.jpg",
    "source_photographer": "https://twitter.com/MyConBestPalPhotographer"
}
```

Then move the folder myconvention into the public/group_pics folder
```
mv myconvention public/group_pics/
```
and restart the webserver.
