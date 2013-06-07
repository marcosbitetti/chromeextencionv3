$ = jQuery

newPosts = 0
icon = null
app = null


##############################
#
# Estrutura de dados de acessp
#
##############################
class Access
	@maxFeeds = 100
	@naoLidos = 0
	@fontesDeFeeds = "# recomendamos (desmarque o # na linha)\n"
			"#http://www.dragoesdosolnegro.com/feeds/posts/default?format=xml\n"+
			"#http://pontosdeexperiencia.blogspot.com/feeds/posts/default?format=xml\n"+
			"#http://dragao-banguela.blogspot.com/feeds/posts/default?format=xml"
	@user = ''
	@mail = ''


##############################
#
# Controla o Ícone da barra do
# navegador
#
##############################
class Icon
	@icons = ["img/19.png"]
	constructor: () ->
		@canvas = document.getElementById "logo"
		@context = @canvas.getContext '2d'
		@image = new Image()
		@image.onload = (e) => @update()
		@image.src = Icon.icons[0]
		@blend = 0
		@cBlend = 0
		@timmerID = null

	# Atualiza o icone na barra do navegador
	update: () =>
		@context.save()
		@context.clearRect 0,0, @canvas.width, @canvas.height
		@context.drawImage @image, 0,0
		if newPosts > 0
			# animation
			#@cBlend += (@blend-@cBlend) * .3
			#r = Math.round(@cBlend*100)
			#if r==0 or r==100
			#	if @blend==0
			#		@blend = 1
			#	else
			#		@blend = 0
			#@context.globalAlpha = @cBlend
			#@context.drawImage @imageGlow, 0,0
			#@context.globalAlpha = 1

			# Se houverem posts não lidos exibe o número
			nPosts = newPosts
			nPosts = "99+" if nPosts>=100
			@context.fillStyle = "#fa0"
			@context.font="bold 10px Arial"
			@context.textAlign="right"
			@context.fillStyle = "#200"
			@context.fillText nPosts,18,13
			@context.fillStyle = "#EEEE00"
			@context.fillText nPosts,17,12

			#if not chrome.runtime
			#	window.clearTimeout @timmerID
			#	@timmerID = window.setTimeout @onAlarm, 120
			#else
			#	chrome.alarms.create 'refresh', {"when":Date.now() + 120}

		@context.restore()

		chrome.browserAction.setIcon {
			imageData:@context.getImageData 0, 0, @canvas.width, @canvas.height
		}
	@reset: () ->
		chrome.browserAction.setIcon {"path":Icon.icons[0]}





##############################
#
# Banco de dados
#
##############################
class DataBase
	@instance = null
	@transaction = null

	# Se não houver base de dados cria uma
	constructor: () ->
		DataBase.instance = this
		@db = window.openDatabase "rpgvale_feed","2.0","rpgvalefeed", 4*1024*1024, (error) -> console.log "CREATE DB " + error.message
		console.log "nao consigo abrir db" if @db==null
		@db.transaction ((tx) ->
			tx.executeSql "CREATE TABLE IF NOT EXISTS posts ( " +
				"_id INTEGER NOT NULL, "+
				"title TEXT NOT NULL,"+
				"pubDate TEXT NOT NULL,"+
				"author TEXT NULL,"+
				"image TEXT NULL,"+
				"link TEXT NOT NULL,"+
				"description TEXT NULL,"+
				"naoLido INTEGER NOT NULL DEFAULT 1"+
				");"), (error) -> console.log "CREATE TABLE " + error.message
		@db.transaction ((tx) ->
			tx.executeSql "CREATE TABLE IF NOT EXISTS access ( " +
				"naoLidos INTEGER NOT NULL, "+
				"user TEXT NULL,"+
				"mail TEXT NULL,"+
				"maxFeeds INTEGER NOT NULL DEFAULT 100,"+
				"fontes TEXT NULL"+
				");"), (error) -> console.log "CREATE TABLE " + error.message
		DataBase.transaction = @m_transaction

	# simples mecanismo para minimizar código
	m_transaction: (query,data,callBack) ->
		DataBase.instance.db.transaction ((tx) =>
				tx.executeSql query, data, ((tx,result) =>
							if callBack != undefined
								callBack tx,result
						)
			), (error) -> console.log "ERRO: " + error.message




##############################
#
# Todas as rotinas do Banco de
# dados para a tabela posts
#
##############################
class FeedsBean
	@clearDataBase = () ->
		DataBase.transaction "DELETE FROM posts", []

	@getFeedsNaoLidos = () ->
		DataBase.transaction "SELECT COUNT(*) AS total FROM posts WHERE naoLido=1", [], ((tx,result) ->
				newPosts = parseInt result.rows.item(0).total
				icon.update()
			)

	@addPost = (i,item) ->
		DataBase.instance.db.transaction ((tx) =>
				tm = item.pubDate
				if item.pubDate.getTime
					tm = item.pubDate.getTime()
				tx.executeSql "INSERT INTO posts (_id,title,pubDate,author,image,link,description) VALUES(?,?,?,?,?,?,?)",
				[ i,item.title,tm,item.author,item.image,item.link,item.description	],
				((tx,result) ->
					# verifica se há muitos posts
					tx.executeSql "SELECT COUNT(_id) AS total FROM posts", [],
						((tx,result) ->
							if parseInt(result.rows.item(0).total)>Access.maxFeeds
								# limpa ultimos timestamp
								console.log "total de feeds atingido"
								tx.executeSql "DELETE FROM posts WHERE pubDate = (SELECT MIN(pubDate) FROM posts)", [], null
						)
				)
			)

	@readPosts = (callBack,data) ->
		DataBase.instance.db.transaction ((tx) =>
				tx.executeSql "SELECT * FROM posts ORDER BY pubDate DESC", [], ((tx, result) =>
					posts = []
					if result.rows.length >0
						for i in [0..result.rows.length-1]
							do (i) =>
								posts.push result.rows.item(i)
					callBack posts, data
					)
				), (error) -> console.log "SELECT readPosts" + error.message

	@insertPosts = (itens) ->
		DataBase.transaction "DELETE FROM posts", [], ( (tx,result) =>
				i = 1
				for item in itens
					do (item) =>
						FeedsBean.addPost i, item
						i += 1
				window.setTimeout FeedsBean.getFeedsNaoLidos, 2000
			)

	@getDuplicate = (callBack) ->
		DataBase.transaction "SELECT _id,pubDate FROM posts WHERE pubDate in (SELECT pubDate FROM posts GROUP BY pubDate HAVING COUNT(*)>1) ORDER BY _id",
				[], callBack

	@deleteEntry = (_id) ->
		DataBase.transaction "DELETE FROM posts WHERE _id=" + _id, []

	@markAllAsARead = () ->
		DataBase.transaction "UPDATE posts SET naoLido=0",[]



##############################
#
# Todas as rotinas do banco de
# dados para a tabela access
#
##############################
class AccessBean
	@getData: (callBack) ->
		DataBase.transaction "SELECT * FROM access LIMIT 1", [], ( (tx,result) =>
				if result.rows.length > 0
					Access.maxFeeds = result.rows.item(0).maxFeeds
					newPosts = Access.naoLidos = result.rows.item(0).naoLidos
					Access.user = result.rows.item(0).user
					Access.mail = result.rows.item(0).mail
					Access.fontesDeFeeds = result.rows.item(0).fontes
				callBack()
			)

	@getMaxFeeds = () ->
		DataBase.instance.db.transaction ((tx) ->
			tx.executeSql "SELECT maxFeeds FROM access", [], ((tx,result) ->
				if result.rows.length==0
					AccessBean.createAccess()
				else
					maxFeeds = parseInt result.rows.item(0).maxFeeds
				)
			), null

	@createAccess = () ->
		DataBase.instance.db.transaction ((tx) =>
				tx.executeSql "INSERT INTO access (naoLidos,user,mail,fontes) VALUES(?,?,?,?)",
				[ 0, "", "", Access.fontesDeFeeds ], ( ()-> AccessBean.getFeedsNaoLidos() )
			), (error) -> console.log "access: " + error.message

	@saveAccess = (moreFeeds, maxFeeds, user, mail) ->
		DataBase.transaction "DELETE FROM access", [], ((tx,result) =>
				user = "" if user == undefined
				mail = "" if mail == undefined
				DataBase.transaction "INSERT INTO access (naoLidos,user,mail,maxFeeds,fontes) VALUES(?,?,?,?,?)",
					[0,user,mail,maxFeeds,moreFeeds]
			)



##############################
#
# Baixa um feed apartir da url
# callBack é uma função que é
# chamada, havendo sucesso ou
# não
#
##############################
class Feed
	constructor: (url, callBack) ->
		@doc = null
		@callBack = callBack
		@itens = []
		@canalImage = ""
		$.ajax {
			url:url
			dataType:"xml"
			"error":@error
			success:@loaded
			contentType:"text/xml; charset=UTF-8"
			processData:false
			converters:{"* text": window.String}
			}

	error: (error) =>
		@callBack this

	# usa o jQuery para transformar o XML em dados
	loaded: (data,textStatus, jqXHR) =>
		if textStatus == 'success'

			# imagem do canal
			cImage = $(data).find "image"
			try
				if cImage
					imageURL = $(cImage[0]).find "url"
					if imageURL
						if imageURL[0].firstChild == undefined
							dt = imageURL[0].nodeValue
						else
							dt = imageURL[0].firstChild.nodeValue
					else
						dt = cImage[0].firstChild.nodeValue
				else
					dt = ""
			catch err
				dt = ""
			@canalImage = dt

			# caça itens
			for item in $(data).find "item"
				do (item) =>
					entry = {
						title: @get item, "title" #$(item).find("title")[0].firstChild.nodeValue,
						description: @convChars @get item, "description" #@convChars($(item).find("description")[0].firstChild.nodeValue),
						pubDate: new Date( @get item, "pubDate") #new Date($(item).find("pubDate")[0].firstChild.nodeValue),
						link: @get item, "link" #$(item).find("link")[0].firstChild.nodeValue,
						author: @get item, "author" #$(item).find("author")[0].firstChild.nodeValue,
						image: null
					}
					entry.image = @getFirstImage entry.description
					@itens.push entry
		@callBack this

	# converte caracteres especiais no texto HTML
	convChars: (str) ->
		str.replace(/&amp;/g, "&").replace(/&gt;/g, ">").replace(/&lt;/g, "<").replace(/&quot;/g, "\"")

	# Localiza a primeira imagem no post
	# Se não localizar retorna a imagem do canal
	getFirstImage: (str) ->
		match = /<img[^>]*/i.exec str
		if match
			a = String(match)
			a = a.substring 5+a.indexOf "src=\""
			a = a.substring 0, a.indexOf "\""
			return a
		return ""

	# retorna um dado do node
	get: (dt, name) =>
		try
			o = $(dt).find name
			if o
				if o[0]
					return o[0].firstChild.nodeValue
		catch error
			return ""
		return ""



##############################
#
# Base do API do Google
#
##############################
class GoogleChromeApp
	constructor: () ->
		@timmerID
		@requestInProgress = false
		@icon = new Icon()
		@oldChromeVersion = !chrome.runtime
		@prepareEvents()
		@onInit()
	prepareEvents: () =>
		if @oldChromeVersion
			@onInstalled()
			chrome.windows.onCreated.addListener onInit
		else
			chrome.runtime.onInstalled.addListener @onInstalled
			chrome.runtime.onStartup.addListener @onInit
			chrome.alarms.onAlarm.addListener @onAlarm
	onInstalled: () =>
	onInit: () =>
	onAlarm: (alarm) =>
	onWatchdog: () =>
	scheduleRequest: (delay) =>
		#console.log 'shedule' + delay
		if @oldChromeVersion
			window.clearTimeout @timmerID
			@timmerID = window.setTimeout @onAlarm, delay
		else
			chrome.alarms.create 'refresh', {"when":Date.now() + delay}  #{"periodInMinutes": delay}




##############################
#
# Classe principal do aplicativo
# que roda em background no navegador
#
##############################
class App extends GoogleChromeApp
	constructor: () ->
		@tdelay = 15 * 60 * 1000 # meia hora
		@popup = new Popup(false)
		chrome.browserAction.onClicked.addListener @popup.show
		chrome.runtime.onMessage.addListener @requestListener
		super

	# manuseia as mensagnes dos outros módulos
	requestListener: (request, sender, sendResponse) =>
		if request.action == 'g_markAllAsARead'
			FeedsBean.markAllAsARead()
			newPosts = 0
			icon.update()

	# reseta a lista de feeds
	updateFeedList: () =>
		@feeds = ["http://feeds.feedburner.com/RpgVale?format=xml"]
		@feedsLoaded = 0
		@feedsToLoad = 1
		
		for fonte in Access.fontesDeFeeds.split "\n"
			do (fonte) =>
				if fonte.length>5
					if fonte.indexOf("#")!=0
						if fonte.indexOf("http://")==-1
							fonte = "http://" + fonte
						if fonte.indexOf("?format=xml")==-1
							fonte += "?format=xml"
						@feeds.push fonte


	run: () =>
		# obtem dados da tabela primária
		# e direciona para run_2
		AccessBean.getData @run_2

	# reseta os @itens e chama todos os feeds da lista
	run_2: () =>
		@updateFeedList()
		@itens = []
		for f in @feeds
			do (f) =>
				new Feed f, @feedCallback

	# recebe os dados processados de um feed
	# quando todos os feeds tiverem sido processados
	# faz a leitura dos feeds no banco e chama a
	# função de comparação.
	feedCallback: (feed) =>
		for i in feed.itens
			do (i) =>
				@itens.push i
		@feedsLoaded += 1
		if @feedsLoaded == @feedsToLoad
			ordenedFeeds = @itens.sort (a,b) =>
				return b.pubDate.getTime()-a.pubDate.getTime()

			if ordenedFeeds.length > 0
				#@itens = ordenedFeeds
				FeedsBean.readPosts @conferePosts, ordenedFeeds

	# confere se existem feeds novos ou se o banco esta vazio
	conferePosts: (oldItens, newItens) =>
		# db vazio?
		if oldItens.length == 0
			FeedsBean.insertPosts newItens
			#AccessBean.setFeedsNaoLidos newItens.length
			#icon.update()
			return

		itens = []
		for item in newItens
			do (item) =>
				notinList = true
				for itemB in oldItens
					do (itemB) =>
						notinList = false if item.title == itemB.title
				if notinList
					itens.push item

		if itens.length > 0
			console.log itens.length
			console.log itens[0].title
			i = oldItens.length+1
			for item in itens
				do (item) =>
					FeedsBean.addPost i, item
					i += 1
		FeedsBean.getDuplicate @confereDuplicados
		#window.setTimeout FeedsBean.getFeedsNaoLidos,2000

	# para evitar casos de duplicidade de entrada
	confereDuplicados: (tx,result) =>
		if result.rows.length>0
			lastPubDate = 0
			for i in [0..result.rows.length-1]
				do (i) =>
					item = result.rows.item(i)
					if item.pubDate == lastPubDate
						FeedsBean.deleteEntry item._id
					if item.pubDate != lastPubDate
						lastPubDate=item.pubDate

	# sobrescritas
	onInit: () =>
		@db = new DataBase()
		console.log "init app"
		@scheduleRequest @tdelay
		#AccessBean.getFeedsNaoLidos()
		FeedsBean.getFeedsNaoLidos()
		@run()

	onAlarm: (alarm) =>
		#console.log('Got alarm', alarm);
		if alarm && alarm.name == 'watchdog'
			@onWatchdog()
		else
			@scheduleRequest @tdelay
		console.log "obter"
		@run()

	onWatchdog: () =>
		chrome.alarms.get 'refresh', (alarm)=>
			@scheduleRequest @tdelay if alarm == undefined or alarm == null




##############################
#
# Classe principal do aplicativo
# que roda em background no navegador
#
##############################
class Popup
	constructor: ( local ) ->
		@db = new DataBase()
		if not local
			chrome.browserAction.setPopup {popup:"popup.html"}
		else
			@list = $ "#posts"
			FeedsBean.readPosts @showPosts

	show:(tab)=>
		chrome.browserAction.setPopup {popup:"popup.html"}

	showPosts: (posts) =>
		chrome.runtime.sendMessage { action: "g_markAllAsARead" }

		@list.children().remove()
		for post in posts
			do (post) =>
				@list.append @thePost post
		if @list.mCustomScrollbar != undefined
			@list.mCustomScrollbar {
					theme: "light-2",
					mouseWheel:true,
					scrollButtons:{	enable:false }
				}
		window._globalList = @list
		$("article img").each (e) -> this.onload = (e) -> window._globalList.mCustomScrollbar "update"

	# template HTML para a entrada do post
	# cada entrada é entregue dentro de um ARTICLE
	thePost: (post) =>
		link = '<a href="'+post.link+'" target="_blank" >'
		img = '<img src="'+post.image+'" alt="'+post.title+'" title="'+post.title+'" />'
		title = '<h4>'+post.title+'</h4>'
		words = post.description.replace(/(<([^>]+)>)/ig,"").replace(/\s{2,}/ig,"").split(" ",32).join(" ") + "..."
		return '<article>'+link+img+'</a><br />'+title+words+'<footer></footer></article>'



##############################################
#
# Tela de opções do sistema
#
##############################################
class Options
	constructor: () ->
		@moreFeeds = $ '#moreFeeds'
		@maxFeeds = $ '#maxFeeds'
		@db = new DataBase()

		@maxFeeds.keyup (e) =>
			@updateDatabase()
			return true
		@moreFeeds.keyup @updateDatabase

		AccessBean.getData @init

	init: () =>
		@moreFeeds.val Access.fontesDeFeeds
		@maxFeeds.val Access.maxFeeds


	updateDatabase: (e) =>
		moreFeeds = @moreFeeds.val()
		maxFeeds = parseInt @maxFeeds.val()
		AccessBean.saveAccess moreFeeds, maxFeeds




##############################################
#
# Rotina de inicialização do sistema
# Todos os módulos (páginas) usam esta rotina
#
##############################################
$ ->
	try
		if String(window.location).indexOf("mainPage.html")>-1
			icon = new Icon()
			app = new App()
		else
			if String(window.location).indexOf("options.html")>-1
				new Options()
			else
				app = new Popup(true)
	catch error
		console.log "alternativo " + error.message
		app = new Popup(true)
