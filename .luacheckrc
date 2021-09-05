read_globals = {
  vim = {
    other_fields = true,
    fields = {
      g = {
        read_only = false,
        other_fields = true
      }
    }
  }
}
include_files = {'lua/', '*.lua'}
std = 'luajit'
