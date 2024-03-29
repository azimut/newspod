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
import Task
import Time exposing (millisToPosix)
import Time.Distance exposing (inWords)


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
    , now : Time.Posix
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
    , date : Int
    , url : String
    , description : String
    , content : String
    , isShowingDetails : Bool
    }


type State
    = Starting
    | Idle
    | WaitingForSearch
    | ShowingResults


type Msg
    = InitFeeds (List InitFeed)
    | InitClock Time.Posix
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
    , date : Int
    , url : String
    }


type alias QuestionEntryDetails =
    { entryId : Int
    , search : String
    }


port askForEntryDetails : QuestionEntryDetails -> Cmd msg


port askForEntries : Int -> Cmd msg


port askForSearch : String -> Cmd msg


port receiveSearchResults : (List NewEntry -> msg) -> Sub msg


port receiveEntries : (List NewEntry -> msg) -> Sub msg


port receiveEntryDetails : (EntryDetails -> msg) -> Sub msg


port receiveInitFeeds : (List InitFeed -> msg) -> Sub msg


init : flags -> ( Model, Cmd Msg )
init _ =
    ( Model [] Dict.empty "" 0 Starting (millisToPosix 0)
    , Task.perform InitClock Time.now
    )


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
update msg ({ feeds, entries, search, now, state } as model) =
    case msg of
        InitFeeds iFeeds ->
            ( Model (List.map toFeed iFeeds) Dict.empty "" 0 Idle now
            , Cmd.none
            )

        InitClock n ->
            ( { model | now = n }, Cmd.none )

        NewInput newSearch ->
            if String.isEmpty (String.trim newSearch) then
                ( { model
                    | feeds = List.map (\feed -> { feed | isVisible = True, isSelected = False }) feeds
                    , entries = Dict.empty
                    , state = Idle
                    , search = ""
                  }
                , Cmd.none
                )

            else
                ( { model | search = newSearch }, Cmd.none )

        AskForSearch ->
            if String.isEmpty (String.trim search) then
                ( model, Cmd.none )

            else
                ( { model | state = WaitingForSearch }, askForSearch search )

        NewSearchResults es ->
            ( newSearchResults model es, Cmd.none )

        AskForEntries feedId ->
            case state of
                Idle ->
                    ( toggleSelectedFeed model feedId, askForEntries feedId )

                _ ->
                    ( toggleSelectedFeed model feedId, Cmd.none )

        NewEntries es ->
            ( newEntries model es, Cmd.none )

        AskForDetails feedId entryId ->
            -- TODO: check if already has details
            ( { model | entries = Dict.update feedId (Maybe.map (toggleEntryDetails entryId)) entries }
            , askForEntryDetails (QuestionEntryDetails entryId search)
            )

        NewDetails ({ feedid } as entryDetails) ->
            ( { model | entries = Dict.update feedid (Maybe.map (fillDetails entryDetails)) entries }
            , Cmd.none
            )


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
    { model | feeds = feeds, entries = entries, state = ShowingResults }


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


viewFeed : Feed -> Time.Posix -> Dict Int (List Entry) -> Html Msg
viewFeed { title, id, nEntries, isSelected } now entries =
    article [ onClick (AskForEntries id) ]
        [ details [ open isSelected ] <|
            summary
                [ if isSelected then
                    class "selected"

                  else
                    class ""
                ]
                [ text (title ++ " [" ++ fromInt nEntries ++ "]") ]
                :: viewFeedEntries id now entries
        ]


viewFeedEntries : Int -> Time.Posix -> Dict Int (List Entry) -> List (Html Msg)
viewFeedEntries feedId now entries =
    List.map (viewEntry feedId now) <|
        Maybe.withDefault [] (Dict.get feedId entries)


onClickWithStopPropagation : msg -> Html.Attribute msg
onClickWithStopPropagation msg =
    stopPropagationOn "click" (JD.map (\m -> ( m, True )) (JD.succeed msg))


viewEntry : Int -> Time.Posix -> Entry -> Html Msg
viewEntry feedId now { title, date, url, id, isShowingDetails, content } =
    div
        [ class "episode"

        -- TODO: do not ask when closing...
        , onClickWithStopPropagation (AskForDetails feedId id)
        ]
        [ div [ class "episode-title" ]
            [ text title ]
        , div [ class "episode-date" ]
            [ a [ href url ]
                [ time [] [ text <| inWords (millisToPosix date) now ] ]
            ]
        , div [ class "episode-content" ]
            [ if isShowingDetails then
                Markdown.toHtml [] content

              else
                div [] []
            ]
        ]


viewHeader : String -> Html Msg
viewHeader search =
    header []
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


viewFooter : Html Msg
viewFooter =
    footer []
        [ div []
            [ a [ href "https://github.com/azimut/newspod" ]
                [ text "source code" ]
            ]
        ]


view : Model -> Html Msg
view { feeds, entries, search, state, now } =
    case state of
        Starting ->
            div [ class "loader" ]
                [ Loaders.ballTriangle 150 "#fff" ]

        Idle ->
            div []
                [ viewHeader search
                , main_ [] <| List.map (\feed -> viewFeed feed now entries) feeds
                , viewFooter
                ]

        WaitingForSearch ->
            div []
                [ viewHeader search
                , div [ class "loader" ]
                    [ Loaders.ballTriangle 150 "#fff" ]
                ]

        ShowingResults ->
            div []
                [ viewHeader search
                , main_ [] <|
                    let
                        filteredFeeds =
                            List.filterMap
                                (\feed ->
                                    if feed.isVisible then
                                        Just (viewFeed feed now entries)

                                    else
                                        Nothing
                                )
                                feeds
                    in
                    case filteredFeeds of
                        [] ->
                            [ text "no results :(" ]

                        fs ->
                            fs
                , viewFooter
                ]


subscriptions : model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ receiveInitFeeds InitFeeds
        , receiveEntries NewEntries
        , receiveEntryDetails NewDetails
        , receiveSearchResults NewSearchResults
        ]
