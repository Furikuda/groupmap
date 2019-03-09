import numpy

# Drop "old" coordinates here. At least 3-4
old = [
    [158.625519752502, -72.1937494277954],
    [16.5630197525024, -69.5062494277954],
    [122.938019752502, -32.7562494277954],
    [69.8130197525024, -35.6937494277954]
]

# Drop "old" coordinates here. At least 3-4
new = [
    [138.886456489563, -62.8854169845581],
    [14.8265624046326, -60.8614583015442],
    [107.695312023163, -28.6093745231628],
    [60.9572877883911, -31.1979169845581]
]

def calc_matrix(old_set, new_set):
    """Returns the transformation matrix."""
    old_array = numpy.array(old_set)
    new_array = numpy.array(new_set)

    #A = numpy.vstack([old_array.T, numpy.ones(4)]).T
    old_matrix = numpy.vstack([old_array])
    m, _, _, _ = numpy.linalg.lstsq(old_matrix, new_array, rcond=None)
    return m

def update(input_file):
    """Does the things"""
    template = 'INSERT INTO fluff (id, name, map, lng, lat, info) VALUES ( NULL, "{name}", "{map}", {lng}, {lat}, "{info}");'
    m = calc_matrix(old, new)
    with open(input_file) as fp:
        for cnt, line in enumerate(fp):
            name,lng,lat,info= line.strip().split(',')
            (new_lng, new_lat) = numpy.dot(m, [float(lng), float(lat)])
            print template.format(name=name, lng=new_lng, lat=new_lat, info=info, map='2019-nfc2')

update('data')
