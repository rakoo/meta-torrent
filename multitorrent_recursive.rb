require 'digest/sha1'
require 'json'
require 'bencode'
require 'base32'
require 'set'

exit unless ARGV[0] and ARGV[1]
ROOTPATH = ARGV[0]

BLOCK_SIZE = 2**20 # 1MB

class Set
  def to_json(*a)
    self.to_a.to_json(*a)
  end

  def self.json_create(o)
    new(*o['data'])
  end
end


module MetaTorrent

  # The tree that will be pre-built on first pass from root to leaves (which are files)
  # and reused on second path to go back to root folder
  # General notice : the folders don't end with a slash. They look exactly
  # the same as files.
  @tree_data = {}
  attr_accessor :tree_data

  def self.build_sub_torrents_and_get_infohash dir
    if @tree_data[dir]['infohash']
      @tree_data[dir]['infohash']
    else
      info_data = {
        'name' => File.basename(dir),
        'files' => @tree_data[dir]['children'].inject([]) do |result, element|
          result.push({'path' => element, 'infohash' => build_sub_torrents_and_get_infohash(element)})
        end
      }.bencode
      infohash = Base32.encode(Digest::SHA1.digest(info_data))
      @tree_data[dir]['infohash'] = infohash

      # write the torrent, which is a dir
      write_torrent info_data

      infohash
    end
  end

  def self.tree_data
    @tree_data
  end

  def self.write_torrent info_data

    # Write the torrent file
    file_path = File.join(ARGV[1], Base32.encode(Digest::SHA1.digest(info_data)) + ".torrent")
    File.open(file_path, 'w', {'encoding' => 'UTF-8'}) do |fh|
      fh.write({
        'announce' => '',
        'info' => info_data
      })
    end

  end

end

# First pass : writing leaves (files) torrents and infohashes in the
# tree_data
Dir.glob(File.join(ROOTPATH, "**/*"), File::FNM_DOTMATCH) do |filename|

  next if filename.match(/\.\./) or File.basename(filename) == "."

  relative_filename = filename.sub(ROOTPATH, "")

  # Fill the infohash_data general hash for later
  parent_path = relative_filename.sub(File.basename(relative_filename), '').sub(/^(.+)\/$/,'\1')
  MetaTorrent.tree_data[parent_path] = {'children' => Set.new } unless MetaTorrent.tree_data[parent_path]
  MetaTorrent.tree_data[parent_path]['children'].add relative_filename

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
    }.bencode

    infohash = Base32.encode(Digest::SHA1.digest(info_data))

    # We have some information we can put in the tree_data
    MetaTorrent.tree_data[relative_filename] = {'infohash' => infohash}

    MetaTorrent.write_torrent info_data

  end

end

# Second pass : writing dir torrents
# We build hashes recursively by simply asking for the infohash of the root
puts MetaTorrent.build_sub_torrents_and_get_infohash("/")
