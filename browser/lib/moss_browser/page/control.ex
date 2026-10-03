defmodule MossBrowser.Page.Control do
  @moduledoc """
  One control on a page, as `Page.Controls` reads it. A struct, so a page of two thousand links shares one set
  of keys instead of carrying its own in each.
  """
  defstruct [
    :id,
    :role,
    :name,
    :type,
    :field,
    :value,
    :hx,
    # what an htmx request of it sends besides its form: hx-vals, as {name, value}
    :vals,
    :href,
    :on,
    :options,
    :desc,
    :form_info,
    :region,
    form: 0,
    section: 0,
    states: []
  ]
end
