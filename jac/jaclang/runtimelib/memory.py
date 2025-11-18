"""Core constructs for Jac Language."""

from __future__ import annotations

from dataclasses import dataclass, field
from pickle import dumps
from shelve import Shelf, open
from typing import Any, Callable, Generator, Generic, Iterable, TypeVar, cast
from uuid import UUID

from .archetype import Anchor, NodeAnchor, Root, TANCH

# import pickle
# from pymongo import MongoClient

ID = TypeVar("ID")


@dataclass
class Memory(Generic[ID, TANCH]):
    """Generic Memory Handler."""

    __mem__: dict[ID, TANCH] = field(default_factory=dict)
    __gc__: set[TANCH] = field(default_factory=set)

    def close(self) -> None:
        """Close memory handler."""
        self.__mem__.clear()
        self.__gc__.clear()

    def is_cached(self, id: ID) -> bool:
        """Check if id if already cached."""
        return id in self.__mem__

    def query(
        self, filter: Callable[[TANCH], bool] | None = None
    ) -> Generator[TANCH, None, None]:
        """Find anchors from memory with filter."""
        return (
            anchor for anchor in self.__mem__.values() if not filter or filter(anchor)
        )

    def all_root(self) -> Generator[Root, None, None]:
        """Get all the roots."""
        for anchor in self.query(lambda anchor: isinstance(anchor.archetype, Root)):
            yield cast(Root, anchor.archetype)

    def find(
        self,
        ids: ID | Iterable[ID],
        filter: Callable[[TANCH], TANCH] | None = None,
    ) -> Generator[TANCH, None, None]:
        """Find anchors from memory by ids with filter."""
        if not isinstance(ids, Iterable):
            ids = [ids]

        return (
            anchor
            for id in ids
            if (anchor := self.__mem__.get(id)) and (not filter or filter(anchor))
        )

    def find_one(
        self,
        ids: ID | Iterable[ID],
        filter: Callable[[TANCH], TANCH] | None = None,
    ) -> TANCH | None:
        """Find one anchor from memory by ids with filter."""
        return next(self.find(ids, filter), None)

    def find_by_id(self, id: ID) -> TANCH | None:
        """Find one by id."""
        return self.__mem__.get(id)

    def set(self, id: ID, data: TANCH) -> None:
        """Save anchor to memory."""
        self.__mem__[id] = data

    def remove(self, ids: ID | Iterable[ID]) -> None:
        """Remove anchor/s from memory."""
        if not isinstance(ids, Iterable):
            ids = [ids]

        for id in ids:
            if anchor := self.__mem__.pop(id, None):
                self.__gc__.add(anchor)

    def commit(self, anchor: TANCH | None = None) -> None:
        """Commit all data from memory to datasource."""


BA = TypeVar("BA", bound="BaseAnchor")


@dataclass
class MongoDB(Memory[UUID, BA]):
    """MongoDB handler storing Python objects (pickled) with behavior exactly like ShelfStorage."""

    client: MongoClient | None = field(default=None)
    db_name: str = "jac_db"
    collection_name: str = "anchors"

    def __post_init__(self):
        if self.client is None:
            self.client = MongoClient(
                "mongodb+srv://juzailmlwork_db_user:e5OTI7p2DkaaGHnL@cluster0.e8eqk4i.mongodb.net/?appName=Cluster0/"
            )
        self.db = self.client[self.db_name]
        self.collection = self.db[self.collection_name]

    # -------------------
    # UTILITY
    # -------------------
    def _to_uuid(self, id: UUID | str) -> UUID:
        if not isinstance(id, UUID):
            return UUID(str(id))
        return id

    def _load_anchor(self, raw: dict[str, Any]):
        try:
            return pickle.loads(raw["data"])
        except Exception:
            return None

    # -------------------
    # FIND
    # -------------------
    def find(
        self,
        ids: UUID | Iterable[UUID],
        filter: callable | None = None,
    ) -> Generator[BA, None, None]:
        if not isinstance(ids, Iterable) or isinstance(ids, (str, bytes)):
            ids = [ids]

        for id in ids:
            _id = self._to_uuid(id)

            # check memory first
            obj = self.__mem__.get(_id)
            if obj:
                if not filter or filter(obj):
                    yield obj
                continue

            # fetch from DB
            db_doc = self.collection.find_one({"_id": str(_id)})
            if db_doc:
                anchor = self._load_anchor(db_doc)
                if anchor is None:
                    continue
                self.__mem__[_id] = anchor
                yield anchor

    # -------------------
    # FIND ONE / BY ID
    # -------------------
    def find_one(self, id: UUID):
        return next(self.find(id), None)

    def find_by_id(self, id: UUID):
        _id = self._to_uuid(id)
        obj = self.__mem__.get(_id)
        if obj:
            return obj

        db_obj = self.collection.find_one({"_id": str(_id)})
        if db_obj:
            anchor = self._load_anchor(db_obj)
            if anchor:
                self.__mem__[_id] = anchor
                return anchor
        return None

    # -------------------
    # COMMIT
    # -------------------
    def commit(self, anchor: BA | None = None) -> None:
        if anchor:
            if anchor in self.__gc__:
                self._delete_anchor(anchor)
            else:
                self._save_anchor(anchor)
            return

        for anc in list(self.__gc__):
            self._delete_anchor(anc)

        for anc in list(self.__mem__.values()):
            self._save_anchor(anc)

    # -------------------
    # INTERNAL SAVE / DELETE
    # -------------------
    def _save_anchor(self, anchor: BA) -> None:
        """
        Save anchor to MongoDB, exactly like ShelfStorage:
        - Save all anchors (no empty NodeAnchor skipping)
        - Update NodeAnchor edges
        - Respect write and connect access
        """
        from jaclang.runtimelib.machine import JacMachineInterface as Jac
        from .archetype import NodeAnchor

        _id = self._to_uuid(anchor.id)

        try:
            current_hash = hash(pickle.dumps(anchor))
        except Exception:
            return

        if getattr(anchor, "hash", None) == current_hash:
            return

        # fetch existing
        db_doc = self.collection.find_one({"_id": str(_id)})
        stored_anchor = self._load_anchor(db_doc) if db_doc else None

        # update edges if NodeAnchor
        if (
            stored_anchor
            and isinstance(stored_anchor, NodeAnchor)
            and isinstance(anchor, NodeAnchor)
            and getattr(stored_anchor, "edges", None) != getattr(anchor, "edges", None)
            and Jac.check_connect_access(anchor)
        ):
            stored_anchor.edges = anchor.edges
            base_anchor = stored_anchor
        else:
            base_anchor = anchor

        # update access/archetype if allowed
        if stored_anchor and Jac.check_write_access(anchor):
            try:
                if hash(pickle.dumps(stored_anchor.access)) != hash(
                    pickle.dumps(anchor.access)
                ):
                    stored_anchor.access = anchor.access
                if hash(pickle.dumps(stored_anchor.archetype)) != hash(
                    pickle.dumps(anchor.archetype)
                ):
                    stored_anchor.archetype = anchor.archetype
                final_anchor = stored_anchor
            except Exception:
                final_anchor = anchor
        else:
            final_anchor = base_anchor

        # save to MongoDB
        try:
            data_blob = pickle.dumps(final_anchor)
        except Exception:
            return

        self.collection.update_one(
            {"_id": str(_id)},
            {"$set": {"data": data_blob, "type": type(final_anchor).__name__}},
            upsert=True,
        )

        self.__mem__[_id] = final_anchor
        final_anchor.hash = current_hash

    def _delete_anchor(self, anchor: BA) -> None:
        _id = self._to_uuid(anchor.id)
        self.collection.delete_one({"_id": str(_id)})
        self.__mem__.pop(_id, None)
        self.__gc__.discard(anchor)

    # -------------------
    # CLOSE
    # -------------------
    def close(self) -> None:
        self.commit()
        super().close()


@dataclass
class ShelfStorage(Memory[UUID, Anchor]):
    """Shelf Handler."""

    __shelf__: Shelf[Anchor] | None = None

    def __init__(self, session: str | None = None) -> None:
        """Initialize memory handler."""
        super().__init__()
        self.__shelf__ = open(session) if session else None  # noqa: SIM115

    def commit(self, anchor: Anchor | None = None) -> None:
        """Commit all data from memory to datasource."""
        if isinstance(self.__shelf__, Shelf):
            if anchor:
                if anchor in self.__gc__:
                    self.__shelf__.pop(str(anchor.id), None)
                    self.__mem__.pop(anchor.id, None)
                    self.__gc__.remove(anchor)
                else:
                    self.sync_mem_to_db([anchor.id])
                return

            for anc in self.__gc__:
                self.__shelf__.pop(str(anc.id), None)
                self.__mem__.pop(anc.id, None)

            keys = set(self.__mem__.keys())

            # current memory
            self.sync_mem_to_db(keys)

            # additional after memory sync
            self.sync_mem_to_db(set(self.__mem__.keys() - keys))

    def close(self) -> None:
        """Close memory handler."""
        self.commit()

        if isinstance(self.__shelf__, Shelf):
            self.__shelf__.close()

        super().close()

    def sync_mem_to_db(self, keys: Iterable[UUID]) -> None:
        """Manually sync memory to db."""
        from jaclang.runtimelib.machine import JacMachineInterface as Jac

        if isinstance(self.__shelf__, Shelf):
            for key in keys:
                if (
                    (d := self.__mem__.get(key))
                    and d.persistent
                    and d.hash != hash(dumps(d))
                ):
                    _id = str(d.id)
                    if p_d := self.__shelf__.get(_id):
                        if (
                            isinstance(p_d, NodeAnchor)
                            and isinstance(d, NodeAnchor)
                            and p_d.edges != d.edges
                            and Jac.check_connect_access(d)
                        ):
                            if not d.edges and not isinstance(d.archetype, Root):
                                self.__shelf__.pop(_id, None)
                                continue
                            p_d.edges = d.edges

                        if Jac.check_write_access(d):
                            if hash(dumps(p_d.access)) != hash(dumps(d.access)):
                                p_d.access = d.access
                            if hash(dumps(p_d.archetype)) != hash(dumps(d.archetype)):
                                p_d.archetype = d.archetype

                        self.__shelf__[_id] = p_d
                    elif not (
                        isinstance(d, NodeAnchor)
                        and not isinstance(d.archetype, Root)
                        and not d.edges
                    ):
                        self.__shelf__[_id] = d

    def query(
        self, filter: Callable[[Anchor], bool] | None = None
    ) -> Generator[Any, None, None]:
        """Find anchors from memory with filter."""
        if isinstance(self.__shelf__, Shelf):
            for anchor in self.__shelf__.values():
                if not filter or filter(anchor):
                    if anchor.id not in self.__mem__:
                        self.__mem__[anchor.id] = anchor
                    yield anchor
        else:
            yield from super().query(filter)

    def find(
        self,
        ids: UUID | Iterable[UUID],
        filter: Callable[[Anchor], Anchor] | None = None,
    ) -> Generator[Anchor, None, None]:
        """Find anchors from datasource by ids with filter."""
        if not isinstance(ids, Iterable):
            ids = [ids]

        if isinstance(self.__shelf__, Shelf):
            for id in ids:
                anchor = self.__mem__.get(id)

                if (
                    not anchor
                    and id not in self.__gc__
                    and (_anchor := self.__shelf__.get(str(id)))
                ):
                    self.__mem__[id] = anchor = _anchor
                if anchor and (not filter or filter(anchor)):
                    yield anchor
        else:
            yield from super().find(ids, filter)

    def find_by_id(self, id: UUID) -> Anchor | None:
        """Find one by id."""
        data = super().find_by_id(id)

        if (
            not data
            and isinstance(self.__shelf__, Shelf)
            and (data := self.__shelf__.get(str(id)))
        ):
            self.__mem__[id] = data

        return data
