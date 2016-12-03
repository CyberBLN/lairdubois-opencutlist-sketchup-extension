class GroupDef

  attr_accessor :name, :raw_thickness
  attr_reader :piece_defs

  def initialize
    @name = ''
    @raw_thickness = 0
    @piece_defs = {}
  end

  def set_piece_def(key, piece_def)
    @piece_defs[key] = piece_def
  end

  def get_piece_def(key)
    if @piece_defs.has_key? key
      return @piece_defs[key]
    end
    nil
  end

end