// This is our magical global env
var groupmap = {
    // The name of the folder with the map, serves as map identifier
    mapFolder: undefined,
    // An array of map metadata
    mapsList: undefined,
    // An array of fluffs
    fluffList: undefined,
    // The marker used to add more fluff
    tempMarker: undefined,
    // The leaflet map object
    leafletMap: undefined,
    // The leaflet markers layer
    markersLayer: undefined,
    // The leaflet control layer
    controlLayer: undefined
};

function make_fluff_popup_text(map_marker) {
    var fluff = get_fluff_from_fluffid(map_marker.fluff_id)
    var html = '<b data-fluff_id="'+map_marker.fluff_id+'" data-id="'+map_marker.id+'">'+fluff.name+'</b>';
    if (fluff.info) {
        html += "<p>";
        html += fluff.info.replace(/(http[^ ]+)/, function(match, url) {return '<a href="' + url + '" target="_blank">' + url + '</a>'});
        html += "</p>";
    }
    return html
}

function add_fluff(fluff, mapFolder) {
    fluff['map'] = mapFolder;
     $.ajax({
        url: "/add_fluff",
        type: "POST",
        dataType: "json",
        data: fluff,
        success: function(data, textStatus) {
            groupmap.tempMarker.closePopup();
            load_fluffs();
            load_fluff_layer(mapFolder);
        },
        error: function(data) {
            console.log(data.responseText);
//            toastr.options.timeOut = 1500;
//            toastr.options.positionClass= "toast-top-center";
//            toastr.error(data.responseText);
        }
    });
}

function get_fluffs_for_autocomplete() {
    var result = {};
    for (var i=0, len=groupmap.fluffList.length; i < len; i++) {
        result[groupmap.fluffList[i]['name']] = null;
    }
    return result;
}

function get_fluff_from_name(name) {
    for (var i=0, len=groupmap.fluffList.length; i < len; i++) {
        var f = groupmap.fluffList[i];
        if (f['name'] == name ) {
            return f
        }
    }
    return null;
}

function get_fluff_from_fluffid(fluff_id) {
    for (var i=0, len=groupmap.fluffList.length; i < len; i++) {
        var f = groupmap.fluffList[i];
        if (f['id'] == fluff_id ) {
            return f
        }
    }
    return null;
}

function show_new_fluff_marker(evt){
    var new_fluff = {};
    var lat = evt.latlng.lat;
    var lng = evt.latlng.lng;

    if (typeof groupmap.tempMarker !== 'undefined') {
        groupmap.tempMarker.unbindPopup();
        groupmap.tempMarker.remove();
    }

    groupmap.tempMarker = L.marker([lat, lng]).addTo(groupmap.markersLayer);

    var popupContent = "<b>Who is that Fluff?</b>"+
        "<form id='add-fluff-form' style='width:15em'>" +
        "<input type='text' name='name' id='add-fluff-name-field' placeholder='Fluff name' class='autocomplete'>" +
        "<input type='text' name='info' id='add-fluff-info-field' placeholder='extra info of link'>" +
        "<input type='hidden' name='lng' id='add-fluff-lng-field' value='"+lng+"'>" +
        "<input type='hidden' name='lat' id='add-fluff-lat-field' value='"+lat+"'>" +
        "<input type='submit' value='Save'>" +
        "</form>";

    groupmap.tempMarker.bindPopup(popupContent).openPopup();
    //groupmap.tempMarker.bindPopup(popupContent, {keepInView: true}).openPopup();

    $('#add-fluff-name-field').autocomplete({
        limit: 5,
        data: get_fluffs_for_autocomplete(),
        onAutocomplete: function(v) {
            var fluff = get_fluff_from_name(v);
            document.getElementById('add-fluff-info-field').value = fluff['info'];
        }
    });

    $('#add-fluff-form').on('submit', function(e) {
        e.preventDefault();
        new_fluff.name = $('#add-fluff-name-field').val();
        new_fluff.info = $('#add-fluff-info-field').val();
        new_fluff.lat = $('#add-fluff-lat-field').val();
        new_fluff.lng = $('#add-fluff-lng-field').val();
        add_fluff(new_fluff, groupmap.mapFolder);
    });
}

function load_fluff_layer(f) {
    $.ajax({
        url: "/list_fluff?map="+f,
        dataType: "json",
        success: function(data, textStatus) {
            groupmap.markersLayer.eachLayer(function (layer) {
                    groupmap.markersLayer.removeLayer(layer);
            });
            for (var i in data['fluffs']) {
                fluff = data['fluffs'][i];
                var popup_content = make_fluff_popup_text(fluff)
                var marker = L.marker([fluff.lat, fluff.lng])
                marker.bindPopup(popup_content);
                marker.addTo(groupmap.markersLayer);
            }
            groupmap.markersLayer.addTo(groupmap.leafletMap);
        },
        error: function(data) {
            console.log(data.responseText);
//            toastr.options.timeOut = 1500;
//            toastr.options.positionClass= "toast-top-center";
//            toastr.error(data.responseText);
        }
    });
}

function get_map_metadata_from_folder(folder) {
    for (var i in groupmap.mapsList) {
        m = groupmap.mapsList[i];
        if (m['folder'] == folder) {
            return m;
        }
    }
    return;
}

function make_map_info_html(map_metadata) {
    var infos = [] ;

    var info_name = ''
    if (map_metadata['name']) {
        info_name = map_metadata['name'];
    } else if (map_metadata['short_name']) {
        info_name = map_metadata['sort_name'];
    }
    if (info_name) {
        if (map_metadata['url']) {
            infos.push('<a href="'+map_metadata['url']+'" target="_blank">'+info_name+'</a>');
        } else {
            infos.push(info_name);
        }
    }

    var p = map_metadata['source_photographer'];
    if (p) {
        if (p.startsWith('http')) {
            infos.push('<a href="'+p+'" target="_blank">'+p+'</a>');
        } else {
            infos.push(p);
        }
    }

    var pic = map_metadata['source_pic'];
    if (pic) {
        var url_pic;
        if (pic.startsWith('http')) {
            url_pic = '<a href="'+pic+'" target="_blank">Full image</a>'
        } else {
            url_pic = '<a href="/group_pics/'+groupmap.mapFolder+'/'+pic+'" target="_blank">Full image</a>'
        }
        infos.push(url_pic);
    }
    return infos.join(' - ');
}

function init_leafletmap(groupmap, max_zoom=7){
    if (typeof groupmap.leafletMap === 'undefined') {
        var map = L.map('map', {
            minZoom: 2,
            maxZoom: max_zoom,
            crs: L.CRS.Simple
        }).setView([-20, 100], 3);
        groupmap.leafletMap = map;
        groupmap.markersLayer = new L.LayerGroup();
        groupmap.controlLayer = L.control.layers(null, {'Toggle markers' : groupmap.markersLayer}, {collapsed: false});
        groupmap.controlLayer.addTo(groupmap.leafletMap);
    }
    groupmap.leafletMap.eachLayer(function (layer) {
            groupmap.leafletMap.removeLayer(layer);
    });
    groupmap.leafletMap.options.maxZoom = max_zoom;
}

function show_map(mapFolder) {
    groupmap.mapFolder = mapFolder;
    var map_metadata = get_map_metadata_from_folder(mapFolder);
    var max_zoom = 7;
    if ('max_zoom' in map_metadata) {
        max_zoom = map_metadata['max_zoom'];
    }
    init_leafletmap(groupmap, maxzoom=max_zoom);

    // Adds the tiles/picture layer
    L.tileLayer('/group_pics/'+mapFolder+'/{z}/{y}/{x}.jpg', {
        noWrap: true,
        attribution: make_map_info_html(map_metadata)
    }).addTo(groupmap.leafletMap);

    // Adds the markers layer
    load_fluff_layer(mapFolder);

    groupmap.leafletMap.on('click', show_new_fluff_marker);
}

function load_maps() {
    load_fluffs();
    if (typeof groupmap.mapsList === 'undefined'){
        $.ajax({
            url: "/list_maps",
            dataType: "json",
            success: function(data, textStatus) {
                groupmap.mapsList = data['maps'];
                if(window.location.hash) {
                    show_map(window.location.hash.split('#')[1]);
                } else {
                    show_map(groupmap.mapsList[0]['folder']);
                }
            },
            error: function(data) {
                console.log(data.responseText);
    //            toastr.options.timeOut = 1500;
    //            toastr.options.positionClass= "toast-top-center";
    //            toastr.error(data.responseText);
            }
        });
    }
}

function load_fluffs() {
   $.ajax({
       url: "/all_fluffs",
       dataType: "json",
       success: function(data, textStatus) {
           groupmap.fluffList = data['fluffs'];
       },
       error: function(data) {
           console.log(data.responseText);
       }
   });
}
