TileMap = require './TileMap'
TileSet = require './TileSet'

module.exports = class TileMapRendererUpdater

  constructor: (@client, @tileMapRenderer, config, @receiveAssetCallbacks, @editAssetCallbacks) ->
    @tileMapAssetId = config.tileMapAssetId
    @tileMapAsset = null

    @tileSetAssetId = config.tileSetAssetId
    @tileSetAsset = null
    @tileSetThreeTexture = null

    @tileMapSubscriber =
      onAssetReceived: @_onTileMapAssetReceived
      onAssetEdited: @_onTileMapAssetEdited
      onAssetTrashed: @_onTileMapAssetTrashed

    @tileSetSubscriber =
      onAssetReceived: @_onTileSetAssetReceived
      onAssetEdited: @_onTileSetAssetEdited
      onAssetTrashed: @_onTileSetAssetTrashed

    if @tileMapAssetId?
      @client.subAsset @tileMapAssetId, 'tileMap', @tileMapSubscriber

  destroy: ->
    if @tileMapAssetId? then @client.unsubAsset @tileMapAssetId, @tileMapSubscriber
    if @tileSetAssetId? then @client.unsubAsset @tileSetAssetId, @tileSetSubscriber
    return

  _onTileMapAssetReceived: (assetId, asset) =>
    @tileMapAsset = asset
    @tileMapRenderer.setTileMap new TileMap @tileMapAsset.pub

    if @tileMapAsset.pub.tileSetId?
      @client.subAsset @tileMapAsset.pub.tileSetId, 'tileSet', @tileSetSubscriber
    @receiveAssetCallbacks?.tileMap();
    return

  _onTileMapAssetEdited: (id, command, args...) =>
    @__proto__["_onEditCommand_#{command}"]?.apply( @, args )
    @editAssetCallbacks?.tileMap[command]? args...
    return

  _onEditCommand_changeTileSet: =>
    @client.unsubAsset @tileSetAssetId, @tileSetSubscriber if @tileSetAssetId?
    @tileSetAsset = null
    @tileMapRenderer.setTileSet null

    @tileSetAssetId = @tileMapAsset.pub.tileSetId
    if @tileSetAssetId?
      @client.subAsset @tileSetAssetId, 'tileSet', @tileSetSubscriber
    return

  _onEditCommand_resizeMap: =>
    @tileMapRenderer.setTileMap new TileMap @tileMapAsset.pub
    return

  _onEditCommand_moveMap: =>
    @tileMapRenderer.refreshEntireMap()
    return

  _onEditCommand_setProperty: (path, value) =>
    switch path
      when "pixelsPerUnit" then @tileMapRenderer.refreshPixelsPerUnit()
      when "layerDepthOffset" then @tileMapRenderer.refreshLayersDepth()
    return

  _onEditCommand_editMap: (layerId, x, y) =>
    index = @tileMapAsset.pub.layers.indexOf @tileMapAsset.layers.byId[layerId]
    @tileMapRenderer.refreshTileAt index, x, y
    return

  _onEditCommand_newLayer: (layer, index) ->
    @tileMapRenderer.addLayer layer, index
    return

  _onEditCommand_deleteLayer: (id, index) ->
    @tileMapRenderer.deleteLayer index
    return

  _onEditCommand_moveLayer: (id, newIndex) ->
    @tileMapRenderer.moveLayer id, newIndex
    return

  _onTileMapAssetTrashed: =>
    @tileMapRenderer.setTileMap null
    if @editAssetCallbacks?
      # FIXME: We should probably have a @trashAssetCallback instead
      # and let editors handle things how they want
      SupClient.onAssetTrashed()
    return

  _onTileSetAssetReceived: (assetId, asset) =>
    @tileSetAsset = asset

    if ! asset.pub.domImage?
      URL.revokeObjectURL @url if @url?
      typedArray = new Uint8Array asset.pub.image
      blob = new Blob [ typedArray ], type: 'image/*'
      @url = URL.createObjectURL blob

      asset.pub.domImage = new Image
      asset.pub.domImage.src = @url

    @tileSetThreeTexture = new SupEngine.THREE.Texture asset.pub.domImage
    @tileSetThreeTexture.magFilter = SupEngine.THREE.NearestFilter
    @tileSetThreeTexture.minFilter = SupEngine.THREE.NearestFilter

    if asset.pub.domImage.complete
      @tileSetThreeTexture.needsUpdate = true
      @tileMapRenderer.setTileSet new TileSet(asset.pub), @tileSetThreeTexture
      @receiveAssetCallbacks?.tileSet();
      return

    onImageLoaded = =>
      asset.pub.domImage.removeEventListener 'load', onImageLoaded
      @tileSetThreeTexture.needsUpdate = true
      @tileMapRenderer.setTileSet new TileSet(asset.pub), @tileSetThreeTexture
      @receiveAssetCallbacks?.tileSet(); return

    asset.pub.domImage.addEventListener 'load', onImageLoaded
    return

  _onTileSetAssetEdited: (id, command, args...) =>
    callEditCallback = true
    if @__proto__["_onTileSetEditCommand_#{command}"]?
      callEditCallback = false if @__proto__["_onTileSetEditCommand_#{command}"].apply( @, args ) == false

    @editAssetCallbacks?.tileSet[command]? args... if callEditCallback
    return

  _onTileSetEditCommand_upload: ->
    URL.revokeObjectURL @url if @url?
    typedArray = new Uint8Array @tileSetAsset.pub.image
    blob = new Blob [ typedArray ], type: 'image/*'
    @url = URL.createObjectURL blob

    image = @tileSetThreeTexture.image
    image.src = @url
    image.addEventListener 'load', =>
      @tileSetThreeTexture.needsUpdate = true
      @tileMapRenderer.setTileSet new TileSet(@tileSetAsset.pub), @tileSetThreeTexture
      return
    return

  _onTileSetEditCommand_setProperty: ->
    @tileMapRenderer.setTileSet new TileSet(@tileSetAsset.pub), @tileSetThreeTexture
    return

  _onTileSetAssetTrashed: =>
    @tileMapRenderer.setTileSet null
    return

  config_setProperty: (path, value) ->
    switch path
      when 'tileMapAssetId'
        @client.unsubAsset @tileMapAssetId, @tileMapSubscriber if @tileMapAssetId?
        @tileMapAssetId = value

        @tileMapAsset = null
        @tileMapRenderer.setTileMap null

        @client.unsubAsset @tileSetAssetId, @tileSetSubscriber if @tileSetAssetId?
        @tileSetAsset = null
        @tileMapRenderer.setTileSet null
        if @tileSetThreeTexture?
          @tileSetThreeTexture.dispose()
          @tileSetThreeTexture = null

        if @tileMapAssetId?
          @client.subAsset @tileMapAssetId, 'tileMap', @tileMapSubscriber

      # when 'tileSetAssetId'

    return
