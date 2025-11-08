# frozen_string_literal: false

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubi'
require 'securerandom'

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, escape_html: true
end

helpers do
  def list_class(list)
    'complete' if list_complete?(list)
  end

  def list_complete?(list)
    todos_count(list).positive? && todos_remaining_count(list).zero?
  end

  def sort_lists(lists, &block)
    complete_lists, incomplete_lists = lists.partition { |list| list_complete? list }

    incomplete_lists.each(&block)
    complete_lists.each(&block)
  end

  def sort_todos(todos, &block)
    complete_todos, incomplete_todos = todos.partition { |todo| todo[:completed] }

    incomplete_todos.each(&block)
    complete_todos.each(&block)
  end

  def todos_count(list)
    list[:todos].size
  end

  def todos_remaining_count(list)
    list[:todos].reduce(0) { |acc, todo| todo[:completed] ? acc : acc + 1 }
  end
end

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    'List name must be between 1 and 100 characters.'
  elsif session[:lists].any? { |list| list[:name] == name }
    'List name must be unique.'
  end
end

# Return an error message if the todo is invalid. Return nil if todo is valid.
def error_for_todo(name)
  return if (1..100).cover? name.size

  'Todo must be between 1 and 100 characters.'
end

def load_list(list_id)
  list = session[:lists].find { |list| list[:id] == list_id }
  return list if list

  session[:error] = 'The specified list was not found.'
  redirect '/lists'
end

def next_element_id(elements)
  max = elements.map { |element| element[:id] }.max || 0
  max + 1
end

before do
  session[:lists] ||= []
end

# Home page redirects to list of lists
get '/' do
  redirect '/lists'
end

# View list of lists
get '/lists' do
  @lists = session[:lists]

  erb :lists, layout: :layout
end

# Render the new list form
get '/lists/new' do
  erb :new_list, layout: :layout
end

# Create a new list
post '/lists' do
  list_name = params[:list_name].strip

  error_message = error_for_list_name(list_name)
  if error_message
    session[:error] = error_message
    erb :new_list, layout: :layout
  else
    id = next_element_id(session[:lists])
    session[:lists] << { id: id, name: list_name, todos: [] }
    session[:success] = 'The list has been created.'
    redirect '/lists'
  end
end

# View a particular list
get '/lists/:list_id' do
  list_id = params[:list_id].to_i
  @list = load_list(list_id)

  erb :list, layout: :layout
end

# Edit an existing todo list
get '/lists/:list_id/edit' do
  list_id = params[:list_id].to_i
  @list = load_list(list_id)

  erb :edit_list
end

# Update an existing todo list
post '/lists/:list_id' do
  list_name = params[:list_name].strip
  list_id = params[:list_id].to_i
  @list = load_list(list_id)

  error_message = error_for_list_name(list_name)
  if error_message
    session[:error] = error_message
    erb :edit_list, layout: :layout
  else
    @list[:name] = list_name
    session[:success] = 'The list has been updated.'
    redirect "/lists/#{@list[:id]}"
  end
end

# Delete a todo list
post '/lists/:list_id/destroy' do
  list_id = params[:list_id].to_i
  session[:lists].reject! { |list| list[:id] == list_id }

  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    '/lists'
  else
    session[:success] = 'The list has been deleted.'
    redirect '/lists'
  end
end

# Add a new todo to a list
post '/lists/:list_id/todos' do
  list_id = params[:list_id].to_i
  @list = load_list(list_id)
  text = params[:todo].strip

  error = error_for_todo(text)
  if error
    session[:error] = error
    erb :list, layout: :layout
  else
    id = next_element_id(@list[:todos])
    @list[:todos] << { id: id, name: text, completed: false }
    session[:success] = 'The todo was added.'
    redirect "/lists/#{@list[:id]}"
  end
end

# Delete a todo from a list
post '/lists/:list_id/todos/:todo_id/destroy' do
  list_id = params[:list_id].to_i
  todo_id = params[:list_id].to_i
  list = load_list(list_id)

  list[:todos].reject! { |todo| todo[:id] == todo_id }
  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    status 204
  else
    session[:success] = 'The todo has been deleted.'
    redirect "/lists/#{list[:id]}"
  end
end

# Mark all todos as complete for a list
post '/lists/:list_id/complete_all' do
  list_id = params[:list_id].to_i
  list = load_list(list_id)

  list[:todos].each { |todo| todo[:completed] = true }
  session[:success] = 'All todos have been completed.'

  redirect "/lists/#{list[:id]}"
end

# Update the status of a todo
post '/lists/:list_id/todos/:todo_id' do
  list_id = params[:list_id].to_i
  list = load_list(list_id)

  todo_id = params[:todo_id].to_i
  is_completed = (params[:completed] == 'true')
  todo = list[:todos].find { |todo| todo[:id] == todo_id }
  todo[:completed] = is_completed

  session[:success] = 'The todo has been updated.'
  redirect "/lists/#{list[:id]}"
end
