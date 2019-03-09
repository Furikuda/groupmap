image_file = ARGV[0]
destination_dir = ARGV[1]

if not (image_file and destination_dir)
  puts "Usage: #{__FILE__} input_pic.jpg destination_dir"
  exit 1
end

$min_width = 20000

def run_command(cmd)
  begin
    io = IO.popen(cmd)
    return io.read()
  rescue Errno::ENOENT
    case cmd[0]
    when "gm"
      raise Exception.new("Please install package graphicsmagick")
    when "vips"
      raise Exception.new("Please install package libvips-tools")
    end
  end
end


width, height = run_command(["gm", "identify", "-format", "%w %h", image_file]).split().map{|x| x.to_i}

new_image_file = image_file

if width < $min_width
  scale = $min_width / width
  new_width = width * scale
  new_height = height * scale
  new_image_file = "big_#{image_file}"
  puts "Resizing #{image_file} to #{new_image_file}"
  run_command(["gm", "convert", "-resize", "#{new_width}x#{new_height}", image_file, new_image_file])
end


puts "Building picture pyramid in folder '#{destination_dir}'"
run_command(["vips", "dzsave", "--layout", "google", new_image_file, destination_dir])

run_command(["cp", image_file, "#{destination_dir}/",])
run_command(["mv", new_image_file, "#{destination_dir}/",])

manifest_path = File.join(destination_dir, "manifest.json")
manifest = File.new(manifest_path, "w")
manifest_string =<<EOMANIFEST
{
    "name": "",
    "shortname": "",
    "year": "#{Time.now.year}",
    "source_pic": "#{new_image_file}",
    "source_photographer": ""
}
EOMANIFEST
puts "Writing to #{manifest_path} :"
puts manifest_string
manifest.write(manifest_string)
puts "Please update #{manifest_path} as necessary"
