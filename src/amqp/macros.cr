macro assert_type(var, type)
  unless {{var.id}}.is_a?({{type.id}})
    raise Protocol::FrameError.new("Unexpected method received: #{{{var.id}}}")
  end
end
