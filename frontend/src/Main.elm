port module Main exposing (..)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, a, article, details, div, footer, form, header, input, main_, span, summary, text, time)
import Html.Attributes exposing (attribute, autofocus, class, href, maxlength, minlength, placeholder, size, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit, stopPropagationOn)
import Json.Decode as JD
import Loaders
import Markdown
import Set
import String exposing (fromInt)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type alias Model =
    { feeds : List Feed
    , entries : Dict Int (List Entry)
    , search : String
    , nResults : Int
    , state : State
    }


type alias Feed =
    { id : Int
    , title : String
    , description : String
    , isSelected : Bool
    , isVisible : Bool
    , nEntries : Int
    }


type alias Entry =
    { id : Int
    , feedid : Int
    , title : String
    , date : String
    , url : String
    , description : String
    , content : String
    , isShowingDetails : Bool
    }


type State
    = Searching
    | Idle


type Msg
    = InitFeeds (List InitFeed)
    | AskForEntries Int
    | NewEntries (List NewEntry)
    | NewInput String
    | AskForDetails Int Int
    | NewDetails EntryDetails
    | AskForSearch
    | NewSearchResults (List NewEntry)


type alias InitFeed =
    { id : Int
    , title : String
    , nEntries : Int
    }


type alias EntryDetails =
    { id : Int
    , feedid : Int
    , description : String
    , content : String
    }


type alias NewEntry =
    { id : Int
    , feedid : Int
    , title : String
    , date : String
    , url : String
    }


port askForEntryDetails : Int -> Cmd msg


port askForEntries : Int -> Cmd msg


port askForSearch : String -> Cmd msg


port receiveSearchResults : (List NewEntry -> msg) -> Sub msg


port receiveEntries : (List NewEntry -> msg) -> Sub msg


port receiveEntryDetails : (EntryDetails -> msg) -> Sub msg


port receiveInitFeeds : (List InitFeed -> msg) -> Sub msg


init : flags -> ( Model, Cmd msg )
init _ =
    ( Model [] Dict.empty "" 0 Idle, Cmd.none )


newEntry : NewEntry -> Entry
newEntry { id, feedid, title, date, url } =
    { id = id
    , feedid = feedid
    , title = title
    , date = date
    , url = url
    , description = ""
    , content = ""
    , isShowingDetails = False
    }


newEntries : Model -> List NewEntry -> Model
newEntries ({ entries } as model) nes =
    case nes of
        [] ->
            model

        entry :: _ ->
            { model | entries = Dict.insert entry.feedid (List.map newEntry nes) entries }


toFeed : InitFeed -> Feed
toFeed { id, title, nEntries } =
    { id = id, title = title, description = "", isSelected = False, isVisible = True, nEntries = nEntries }


toggleEntryDetails : Int -> List Entry -> List Entry
toggleEntryDetails id =
    List.map
        (\entry ->
            if entry.id == id then
                { entry | isShowingDetails = not entry.isShowingDetails }

            else
                entry
        )


fillDetails : EntryDetails -> List Entry -> List Entry
fillDetails eDetails =
    List.map
        (\entry ->
            if entry.id == eDetails.id then
                { entry | content = eDetails.content, description = eDetails.description }

            else
                entry
        )


update : Msg -> Model -> ( Model, Cmd msg )
update msg ({ feeds, entries, search } as model) =
    case msg of
        AskForSearch ->
            if String.isEmpty (String.trim search) then
                ( { model
                    | feeds = List.map (\feed -> { feed | isVisible = True, isSelected = False }) feeds
                    , search = ""
                  }
                , Cmd.none
                )

            else
                ( { model | state = Searching }, askForSearch search )

        AskForDetails feedId entryId ->
            -- TODO: check if already has details
            ( { model | entries = Dict.update feedId (Maybe.map (toggleEntryDetails entryId)) entries }
            , askForEntryDetails entryId
            )

        NewDetails ({ feedid } as entryDetails) ->
            ( { model | entries = Dict.update feedid (Maybe.map (fillDetails entryDetails)) entries }
            , Cmd.none
            )

        NewInput newSearch ->
            ( { model | search = newSearch }, Cmd.none )

        AskForEntries feedId ->
            if Dict.member feedId entries then
                ( toggleSelectedFeed model feedId, Cmd.none )

            else
                ( toggleSelectedFeed model feedId, askForEntries feedId )

        InitFeeds iFeeds ->
            ( Model (List.map toFeed iFeeds) Dict.empty "" 0 Idle
            , Cmd.none
            )

        NewEntries es ->
            ( newEntries model es, Cmd.none )

        NewSearchResults es ->
            ( newSearchResults model es, Cmd.none )


newSearchResults : Model -> List NewEntry -> Model
newSearchResults model nEntries =
    let
        feedIds =
            List.foldl (\e acc -> Set.insert e.feedid acc) Set.empty nEntries

        feeds =
            List.map
                (\feed ->
                    let
                        isMember =
                            Set.member feed.id feedIds
                    in
                    { feed | isSelected = isMember, isVisible = isMember }
                )
                model.feeds

        entries =
            List.foldl
                (\entry ->
                    Dict.update entry.feedid
                        (\foo ->
                            case foo of
                                Nothing ->
                                    Just [ entry ]

                                Just bar ->
                                    Just (entry :: bar)
                        )
                )
                Dict.empty
                (List.map newEntry nEntries)
    in
    { model | feeds = feeds, entries = entries, state = Idle }


toggleSelectedFeed : Model -> Int -> Model
toggleSelectedFeed ({ feeds, entries } as model) feedid =
    { model
        | feeds =
            List.map
                (\feed ->
                    if feed.id == feedid then
                        { feed | isSelected = not feed.isSelected }

                    else
                        feed
                )
                feeds
        , entries =
            Dict.update feedid
                (Maybe.map
                    (List.map
                        (\entry ->
                            if entry.isShowingDetails then
                                { entry | isShowingDetails = False }

                            else
                                entry
                        )
                    )
                )
                entries
    }


open : Bool -> Html.Attribute msg
open flag =
    if flag then
        attribute "open" ""

    else
        class ""


viewFeed : Feed -> Dict Int (List Entry) -> Html Msg
viewFeed { title, id, nEntries, isSelected } entries =
    article [ onClick (AskForEntries id) ]
        [ details [ open isSelected ] <|
            summary
                [ if isSelected then
                    class "selected"

                  else
                    class ""
                ]
                [ text (title ++ " [" ++ fromInt nEntries ++ "]") ]
                :: viewFeedEntries id entries
        ]


viewFeedEntries : Int -> Dict Int (List Entry) -> List (Html Msg)
viewFeedEntries feedId entries =
    List.map (viewEntry feedId) <|
        Maybe.withDefault [] (Dict.get feedId entries)


onClickWithStopPropagation : msg -> Html.Attribute msg
onClickWithStopPropagation msg =
    stopPropagationOn "click" (JD.map (\m -> ( m, True )) (JD.succeed msg))


viewEntry : Int -> Entry -> Html Msg
viewEntry feedId { title, date, url, id, isShowingDetails, content } =
    div
        [ class "episode"

        -- TODO: do not ask when closing...
        , onClickWithStopPropagation (AskForDetails feedId id)
        ]
        [ div [ class "episode-title" ]
            [ text title ]
        , div [ class "episode-date" ]
            [ a [ href url ]
                [ time [] [ text date ] ]
            ]
        , if isShowingDetails then
            Markdown.toHtml [] content

          else
            div [] []
        ]


view : Model -> Html Msg
view { feeds, entries, search, state } =
    case feeds of
        [] ->
            div [ class "loader" ]
                [ Loaders.ballTriangle 150 "#fff" ]

        _ ->
            div []
                [ header []
                    [ text "news"
                    , span [ class "pod" ] [ text "pod" ]
                    , form [ onSubmit AskForSearch ]
                        [ input
                            [ type_ "search"
                            , placeholder "search..."
                            , value search
                            , onInput NewInput
                            , minlength 3
                            , maxlength 30
                            , size 12
                            , autofocus True
                            ]
                            []
                        ]
                    ]
                , main_ [] <|
                    let
                        filteredFeeds =
                            List.filterMap
                                (\feed ->
                                    if feed.isVisible then
                                        Just (viewFeed feed entries)

                                    else
                                        Nothing
                                )
                                feeds
                    in
                    case filteredFeeds of
                        [] ->
                            [ text "no results :(" ]

                        fs ->
                            case state of
                                Idle ->
                                    fs

                                Searching ->
                                    [ div [ class "loader" ]
                                        [ Loaders.ballTriangle 150 "#fff" ]
                                    ]
                , footer []
                    [ div []
                        [ a [ href "https://github.com/azimut/newspod" ]
                            [ text "source code" ]
                        ]
                    ]
                ]


subscriptions : model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ receiveInitFeeds InitFeeds
        , receiveEntries NewEntries
        , receiveEntryDetails NewDetails
        , receiveSearchResults NewSearchResults
        ]
