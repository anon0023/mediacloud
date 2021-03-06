from mediawords.db import DatabaseHandler
from mediawords.util.extract_text import extractor_name
from mediawords.util.perl import decode_object_from_bytes_if_needed


def extractor_version_tag_sets_name() -> str:
    return 'extractor_version'


def update_extractor_version_tag(db: DatabaseHandler, story: dict) -> None:
    """Add extractor version tag to the story."""
    # FIXME no caching because unit tests run in the same process so a cached tag set / tag will not be recreated.
    # Purging such a cache manually is very error-prone.

    story = decode_object_from_bytes_if_needed(story)

    tag_set = db.find_or_create(table='tag_sets', insert_hash={'name': extractor_version_tag_sets_name()})

    db.query("""
        DELETE FROM stories_tags_map AS stm
            USING tags AS t
                JOIN tag_sets AS ts
                    ON ts.tag_sets_id = t.tag_sets_id
        WHERE t.tags_id = stm.tags_id
          AND ts.tag_sets_id = %(tag_sets_id)s
          AND stm.stories_id = %(stories_id)s
    """, {
        'tag_sets_id': tag_set['tag_sets_id'],
        'stories_id': story['stories_id'],
    })

    extractor_version = extractor_name()
    tag = db.find_or_create(table='tags', insert_hash={'tag': extractor_version, 'tag_sets_id': tag_set['tag_sets_id']})
    tags_id = tag['tags_id']

    db.query("""
        INSERT INTO stories_tags_map (stories_id, tags_id)
        VALUES (%(stories_id)s, %(tags_id)s)
    """, {'stories_id': story['stories_id'], 'tags_id': tags_id})
