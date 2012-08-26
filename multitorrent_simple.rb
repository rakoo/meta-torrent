require 'digest/sha1'
require 'json'
require 'bencode'
require 'base32'

exit unless ARGV[0] and ARGV[1]
ROOTPATH = ARGV[0]

BLOCK_SIZE = 2**20 # 1MB

#class Set
  #def to_json(*a)
    ##self.to_a.to_json(*a)
  ##end

  ##def self.json_create(o)
    ##new(*o['data'])
  ##end
#end

dir_torrent = {
  'announce' => '',
  'info' => {
    'files' => []
  }
}

# First pass : writing leaves (files) torrents and infohashes in the
# tree_data
Dir.glob(File.join(ROOTPATH, "**/*"), File::FNM_DOTMATCH) do |filename|

  next if filename.match(/\.\./) or File.basename(filename) == "."

  relative_filename = filename.sub(ROOTPATH, "")

  # Treat the filename if it is a file
  if File.file? filename
    block_number = File.size(filename) / BLOCK_SIZE

    # Calculate pieces
    pieces = ""
    File.open(filename) do |fh|
      count = 0
      while piece = fh.read(BLOCK_SIZE)
        count+=1
        puts "file #{relative_filename} : block #{count}/#{block_number}" if count % 100 == 0
        pieces << Digest::SHA1.digest(piece)
      end
    end

    # Build the info hash map
    info_data = {
      'name' => File.basename(relative_filename),
      'piece_length' => BLOCK_SIZE,
      'length' => File.size(filename),
      'pieces' => pieces
    }

    infohash = Base32.encode(Digest::SHA1.digest(info_data.bencode))

    dir_torrent['info']['files'].push({
      'path' => relative_filename,
      'infohash' => infohash
    })
    
    # Write the torrent file
    file_path = File.join(ARGV[1], Base32.encode(Digest::SHA1.digest(info_data.bencode)) + ".torrent")
    File.open(file_path, 'w', {'encoding' => 'UTF-8'}) do |fh|
      fh.write({
        'announce' => '',
        'info' => info_data
      }.bencode)
    end


  end

end

dir_torrent['info'].merge({
  'name' => ROOTPATH,
  'piece_length' => 0,
})

# Write the torrent file
file_path = File.join(ARGV[1], Base32.encode(Digest::SHA1.digest(dir_torrent['info'].bencode)) + ".torrent")
File.open(file_path, 'w', {'encoding' => 'UTF-8'}) do |fh|
  fh.write(dir_torrent.bencode)
end
